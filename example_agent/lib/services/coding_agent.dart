import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gguf/flutter_gguf.dart';
import '../models/agent_state.dart';
import 'workspace_service.dart';

/// Autonomous ReAct Coding Agent executing on-device via flutter_gguf.
class CodingAgent extends ChangeNotifier {
  final WorkspaceService workspace;

  LlamaModel? _model;
  bool _isLoadingModel = false;
  bool _isRunningTask = false;
  bool _shouldCancel = false;
  String? _modelPath;
  ModelInfo? _modelInfo;
  double _lastTokensPerSec = 0.0;
  StreamSubscription<String>? _currentSubscription;

  final List<AgentTrajectoryStep> _trajectory = [];
  final List<AgentTool> _tools = [];

  CodingAgent({required this.workspace}) {
    _registerTools();
  }

  bool get isModelLoaded => _model != null;
  bool get isLoadingModel => _isLoadingModel;
  bool get isRunningTask => _isRunningTask;
  String? get modelPath => _modelPath;
  ModelInfo? get modelInfo => _modelInfo;
  double get lastTokensPerSec => _lastTokensPerSec;
  List<AgentTrajectoryStep> get trajectory => List.unmodifiable(_trajectory);
  List<AgentTool> get tools => List.unmodifiable(_tools);

  void _registerTools() {
    _tools.addAll([
      AgentTool(
        name: 'read_file',
        description: 'Read the text content of a file from the workspace.',
        parameters: const [
          ToolParam(name: 'path', type: 'string', description: 'Relative path to the file (e.g. lib/calculator.dart).'),
        ],
        handler: (args) async {
          final path = args['path']?.toString() ?? '';
          final content = workspace.readFile(path);
          if (content == null) {
            return 'Error: File "$path" does not exist in workspace.';
          }
          return content;
        },
      ),
      AgentTool(
        name: 'write_file',
        description: 'Write or overwrite a file in the workspace with new code content.',
        parameters: const [
          ToolParam(name: 'path', type: 'string', description: 'Relative path to the file (e.g. lib/math_utils.dart).'),
          ToolParam(name: 'content', type: 'string', description: 'Complete file content to write.'),
        ],
        handler: (args) async {
          final path = args['path']?.toString() ?? '';
          final content = args['content']?.toString() ?? '';
          if (path.isEmpty) return 'Error: path cannot be empty.';
          workspace.writeFile(path, content);
          return 'Success: File "$path" written (${content.split('\n').length} lines).';
        },
      ),
      AgentTool(
        name: 'list_files',
        description: 'List all files currently in the workspace or a subdirectory.',
        parameters: const [
          ToolParam(name: 'directory', type: 'string', description: 'Optional directory prefix (e.g. lib/).', isRequired: false),
        ],
        handler: (args) async {
          final dir = args['directory']?.toString();
          final files = workspace.listFiles(dir);
          if (files.isEmpty) return 'No files found in workspace.';
          return files.map((f) => '- $f').join('\n');
        },
      ),
      AgentTool(
        name: 'search_code',
        description: 'Search across all files for matching string or keyword.',
        parameters: const [
          ToolParam(name: 'query', type: 'string', description: 'Search term or symbol name.'),
        ],
        handler: (args) async {
          final query = args['query']?.toString() ?? '';
          return workspace.searchCode(query);
        },
      ),
      AgentTool(
        name: 'analyze_syntax',
        description: 'Run syntax and structure validator on a file to detect unclosed brackets or errors.',
        parameters: const [
          ToolParam(name: 'path', type: 'string', description: 'File path to analyze (e.g. lib/calculator.dart).'),
        ],
        handler: (args) async {
          final path = args['path']?.toString() ?? '';
          return workspace.analyzeSyntax(path);
        },
      ),
    ]);
  }

  /// Load a GGUF model for the coding agent.
  Future<void> loadModel(String path, {ModelParams params = const ModelParams(contextSize: 4096, threads: 4)}) async {
    _isLoadingModel = true;
    notifyListeners();

    try {
      if (_model != null) {
        _model!.dispose();
        _model = null;
      }
      _model = await LlamaModel.load(path, params: params);
      _modelPath = path;
      _modelInfo = _model!.info;
    } finally {
      _isLoadingModel = false;
      notifyListeners();
    }
  }

  void cancelTask() {
    _shouldCancel = true;
    _currentSubscription?.cancel();
    _currentSubscription = null;
    _isRunningTask = false;
    notifyListeners();
  }

  void clearTrajectory() {
    _trajectory.clear();
    notifyListeners();
  }

  /// Format messages into ChatML prompt string.
  String formatChatML(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      buffer.writeln('<|im_start|>${msg.role}\n${msg.content}<|im_end|>');
    }
    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }

  /// Run an autonomous multi-step coding task.
  Future<void> executeTask(
    String userPrompt, {
    SamplingParams samplingParams = const SamplingParams(temperature: 0.2, topP: 0.95),
    int maxSteps = 8,
  }) async {
    if (_model == null) {
      throw StateError('Please load a GGUF model first.');
    }
    if (_isRunningTask) return;

    _isRunningTask = true;
    _shouldCancel = false;

    // 1. Add User Prompt Step
    _trajectory.add(
      AgentTrajectoryStep(
        id: UniqueKey().toString(),
        type: AgentStepType.userRequest,
        content: userPrompt,
      ),
    );
    notifyListeners();

    // 2. Build conversation context
    final conversation = <ChatMessage>[
      ChatMessage.system(_buildSystemPrompt()),
      ChatMessage.user(userPrompt),
    ];

    int currentStepIndex = 0;

    try {
      while (!_shouldCancel && currentStepIndex < maxSteps) {
        currentStepIndex++;

        // Add thinking step
        final stepId = UniqueKey().toString();
        var currentStep = AgentTrajectoryStep(
          id: stepId,
          type: AgentStepType.thinking,
          content: '',
        );
        _trajectory.add(currentStep);
        notifyListeners();

        // Format prompt for the model
        final formattedPrompt = formatChatML(conversation);
        final tokenBuffer = StringBuffer();

        final completer = Completer<void>();

        // Stream model response
        final stream = _model!.generate(
          formattedPrompt,
          params: samplingParams,
          onStats: (stats) {
            _lastTokensPerSec = stats.tokensPerSecond;
          },
        );

        _currentSubscription = stream.listen(
          (token) {
            if (_shouldCancel) {
              _currentSubscription?.cancel();
              if (!completer.isCompleted) completer.complete();
              return;
            }
            tokenBuffer.write(token);
            currentStep = currentStep.copyWith(
              content: tokenBuffer.toString(),
              tokensPerSecond: _lastTokensPerSec,
            );
            _trajectory[_trajectory.length - 1] = currentStep;
            notifyListeners();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (Object error) {
            if (!completer.isCompleted) completer.completeError(error);
          },
        );

        await completer.future;

        if (_shouldCancel) break;

        final fullOutput = tokenBuffer.toString().trim();
        conversation.add(ChatMessage.assistant(fullOutput));

        // Check if the agent called a tool
        final toolCall = _parseToolCall(fullOutput);

        if (toolCall != null) {
          // Update step to executing tool
          currentStep = currentStep.copyWith(
            type: AgentStepType.toolExecuting,
            toolInvocation: toolCall,
          );
          _trajectory[_trajectory.length - 1] = currentStep;
          notifyListeners();

          // Execute the tool
          final tool = _tools.firstWhere(
            (t) => t.name == toolCall.toolName,
            orElse: () => AgentTool(
              name: 'unknown',
              description: '',
              parameters: [],
              handler: (args) async => 'Error: Tool "${toolCall.toolName}" is not recognized.',
            ),
          );

          final result = await tool.handler(toolCall.arguments);

          // Update step with tool result
          currentStep = currentStep.copyWith(
            type: AgentStepType.toolExecuted,
            toolOutput: result,
          );
          _trajectory[_trajectory.length - 1] = currentStep;
          notifyListeners();

          // Feed observation back into conversation
          conversation.add(
            ChatMessage.user(
              'Observation from ${toolCall.toolName}:\n$result\n\nContinue with your next step or provide your final response.',
            ),
          );
        } else {
          // Final answer reached
          currentStep = currentStep.copyWith(
            type: AgentStepType.finalAnswer,
          );
          _trajectory[_trajectory.length - 1] = currentStep;
          notifyListeners();
          break;
        }
      }
    } catch (e) {
      _trajectory.add(
        AgentTrajectoryStep(
          id: UniqueKey().toString(),
          type: AgentStepType.error,
          content: 'Agent error: $e',
        ),
      );
    } finally {
      _isRunningTask = false;
      _currentSubscription = null;
      notifyListeners();
    }
  }

  String _buildSystemPrompt() {
    final buffer = StringBuffer();
    buffer.writeln('You are an expert autonomous Mobile Coding Agent.');
    buffer.writeln('You can inspect files, write code, run syntax checks, and solve coding requests in the workspace.');
    buffer.writeln();
    buffer.writeln('Available Tools:');
    for (final t in _tools) {
      buffer.write(t.toPromptString());
    }
    buffer.writeln();
    buffer.writeln('Instructions:');
    buffer.writeln('1. When you need to read, write, or search code, call ONE tool per turn using JSON format:');
    buffer.writeln('```json');
    buffer.writeln('{"action": "tool_name", "arguments": {"param1": "value1"}}');
    buffer.writeln('```');
    buffer.writeln('2. Do not explain your tool call before executing it; directly output the JSON block or your reasoning.');
    buffer.writeln('3. Once you have finished all tasks, reply with a concise final summary without any tool call JSON.');
    return buffer.toString();
  }

  ToolInvocation? _parseToolCall(String response) {
    // 1. Try markdown JSON block: ```json { "action": ... } ```
    final jsonBlockMatch = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```', caseSensitive: false).firstMatch(response);
    if (jsonBlockMatch != null) {
      final jsonStr = jsonBlockMatch.group(1);
      if (jsonStr != null) {
        final parsed = _tryDecodeToolJson(jsonStr, response);
        if (parsed != null) return parsed;
      }
    }

    // 2. Try XML tag: <tool_call>{ ... }</tool_call>
    final xmlMatch = RegExp(r'<tool_call>\s*(\{[\s\S]*?\})\s*<\/tool_call>', caseSensitive: false).firstMatch(response);
    if (xmlMatch != null) {
      final jsonStr = xmlMatch.group(1);
      if (jsonStr != null) {
        final parsed = _tryDecodeToolJson(jsonStr, response);
        if (parsed != null) return parsed;
      }
    }

    // 3. Scan for opening { and matching closing }
    int searchIdx = 0;
    while (searchIdx < response.length) {
      final start = response.indexOf('{', searchIdx);
      if (start == -1) break;
      int braceDepth = 0;
      int end = -1;
      for (int i = start; i < response.length; i++) {
        if (response[i] == '{') {
          braceDepth++;
        } else if (response[i] == '}') {
          braceDepth--;
          if (braceDepth == 0) {
            end = i;
            break;
          }
        }
      }
      if (end != -1) {
        final candidate = response.substring(start, end + 1);
        final parsed = _tryDecodeToolJson(candidate, response);
        if (parsed != null) return parsed;
        searchIdx = end + 1;
      } else {
        break;
      }
    }

    return null;
  }

  ToolInvocation? _tryDecodeToolJson(String jsonStr, String raw) {
    try {
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        final action = decoded['action'] ?? decoded['name'] ?? decoded['tool'];
        if (action is String) {
          final rawArgs = decoded['arguments'] ?? decoded['args'] ?? decoded['parameters'];
          final Map<String, dynamic> args;
          if (rawArgs is Map<String, dynamic>) {
            args = rawArgs;
          } else {
            args = Map<String, dynamic>.from(decoded)..removeWhere((k, v) => k == 'action' || k == 'name' || k == 'tool');
          }
          return ToolInvocation(
            toolName: action,
            arguments: args,
            rawCall: jsonStr,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _model?.dispose();
    super.dispose();
  }
}
