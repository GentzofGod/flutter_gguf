import 'dart:convert';

/// Representation of a tool parameter.
class ToolParam {
  final String name;
  final String type;
  final String description;
  final bool isRequired;

  const ToolParam({
    required this.name,
    required this.type,
    required this.description,
    this.isRequired = true,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'description': description,
        'required': isRequired,
      };
}

/// Representation of a tool callable by the agent.
class AgentTool {
  final String name;
  final String description;
  final List<ToolParam> parameters;
  final Future<String> Function(Map<String, dynamic> args) handler;

  const AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.handler,
  });

  String toPromptString() {
    final buffer = StringBuffer();
    buffer.writeln('- `$name`: $description');
    buffer.writeln('  Parameters:');
    for (final p in parameters) {
      buffer.writeln('    - `${p.name}` (${p.type}${p.isRequired ? ', required' : ', optional'}): ${p.description}');
    }
    return buffer.toString();
  }
}

/// A single tool call invocation by the agent.
class ToolInvocation {
  final String toolName;
  final Map<String, dynamic> arguments;
  final String rawCall;

  const ToolInvocation({
    required this.toolName,
    required this.arguments,
    required this.rawCall,
  });

  @override
  String toString() => '$toolName(${jsonEncode(arguments)})';
}

/// Step status in the agent lifecycle.
enum AgentStepType {
  userRequest,
  thinking,
  toolExecuting,
  toolExecuted,
  finalAnswer,
  error,
}

/// An individual step/entry in the agent trajectory.
class AgentTrajectoryStep {
  final String id;
  final AgentStepType type;
  final String content;
  final ToolInvocation? toolInvocation;
  final String? toolOutput;
  final DateTime timestamp;
  final double? tokensPerSecond;

  AgentTrajectoryStep({
    required this.id,
    required this.type,
    required this.content,
    this.toolInvocation,
    this.toolOutput,
    DateTime? timestamp,
    this.tokensPerSecond,
  }) : timestamp = timestamp ?? DateTime.now();

  AgentTrajectoryStep copyWith({
    AgentStepType? type,
    String? content,
    ToolInvocation? toolInvocation,
    String? toolOutput,
    double? tokensPerSecond,
  }) {
    return AgentTrajectoryStep(
      id: id,
      type: type ?? this.type,
      content: content ?? this.content,
      toolInvocation: toolInvocation ?? this.toolInvocation,
      toolOutput: toolOutput ?? this.toolOutput,
      timestamp: timestamp,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
    );
  }
}

/// Virtual or local workspace file.
class WorkspaceFile {
  final String path;
  String content;
  DateTime lastModified;
  bool isCreatedByAgent;
  bool isModifiedByAgent;

  WorkspaceFile({
    required this.path,
    required this.content,
    DateTime? lastModified,
    this.isCreatedByAgent = false,
    this.isModifiedByAgent = false,
  }) : lastModified = lastModified ?? DateTime.now();

  int get lineCount => content.split('\n').length;
  int get byteSize => utf8.encode(content).length;
}
