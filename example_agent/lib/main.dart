import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gguf/flutter_gguf.dart';
import 'models/agent_state.dart';
import 'services/coding_agent.dart';
import 'services/workspace_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CodingAgentApp());
}

class CodingAgentApp extends StatelessWidget {
  const CodingAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Coding Agent (flutter_gguf)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF64B5F6),
          secondary: const Color(0xFF81C784),
          surface: const Color(0xFF1E1E2E),
          surfaceContainerLowest: const Color(0xFF181825),
        ),
        scaffoldBackgroundColor: const Color(0xFF11111B),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const CodingAgentHomePage(),
    );
  }
}

class CodingAgentHomePage extends StatefulWidget {
  const CodingAgentHomePage({super.key});

  @override
  State<CodingAgentHomePage> createState() => _CodingAgentHomePageState();
}

class _CodingAgentHomePageState extends State<CodingAgentHomePage> {
  late final WorkspaceService _workspace;
  late final CodingAgent _agent;
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _trajectoryScroll = ScrollController();

  int _selectedTabIndex = 0;
  String? _selectedFilePath;
  bool _showDiffView = false;
  double _temperature = 0.2;
  double _topP = 0.95;
  int _nThreads = 4;
  int _nCtx = 4096;
  int _maxSteps = 8;

  @override
  void initState() {
    super.initState();
    _workspace = WorkspaceService()..addListener(() => setState(() {}));
    _agent = CodingAgent(workspace: _workspace)..addListener(() => setState(() {}));
    _selectedFilePath = _workspace.filePaths.firstOrNull;
  }

  @override
  void dispose() {
    _workspace.dispose();
    _agent.dispose();
    _promptController.dispose();
    _trajectoryScroll.dispose();
    super.dispose();
  }

  Future<void> _pickModel() async {
    try {
      final path = await FlutterGguf.pickModelFile();
      if (path != null && mounted) {
        await _agent.loadModel(
          path,
          params: ModelParams(contextSize: _nCtx, threads: _nThreads),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load model: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _runTask(String prompt) {
    if (prompt.trim().isEmpty) return;
    _promptController.clear();
    FocusScope.of(context).unfocus();

    _agent.executeTask(
      prompt.trim(),
      samplingParams: SamplingParams(temperature: _temperature, topP: _topP),
      maxSteps: _maxSteps,
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_trajectoryScroll.hasClients) {
        _trajectoryScroll.animateTo(
          _trajectoryScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildTrajectoryTab(),
          _buildWorkspaceTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (idx) => setState(() => _selectedTabIndex = idx),
        backgroundColor: const Color(0xFF181825),
        indicatorColor: const Color(0xFF64B5F6).withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology, color: Color(0xFF64B5F6)),
            label: 'Agent',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_open_outlined),
            selectedIcon: Icon(Icons.folder, color: Color(0xFF81C784)),
            label: 'Workspace',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune, color: Color(0xFFFFB74D)),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF181825),
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF64B5F6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.terminal, color: Color(0xFF64B5F6), size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mobile Coding Agent',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                'Powered by flutter_gguf',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (_agent.lastTokensPerSec > 0)
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF81C784).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF81C784).withValues(alpha: 0.3)),
              ),
              child: Text(
                '${_agent.lastTokensPerSec.toStringAsFixed(1)} tok/s',
                style: const TextStyle(fontSize: 11, color: Color(0xFF81C784), fontWeight: FontWeight.bold),
              ),
            ),
          ),
        IconButton(
          tooltip: 'Select GGUF Model',
          icon: Icon(
            _agent.isModelLoaded ? Icons.check_circle : Icons.upload_file,
            color: _agent.isModelLoaded ? const Color(0xFF81C784) : const Color(0xFF64B5F6),
          ),
          onPressed: _agent.isLoadingModel ? null : _pickModel,
        ),
      ],
    );
  }

  // ================= TAB 1: AGENT TRAJECTORY =================
  Widget _buildTrajectoryTab() {
    if (!_agent.isModelLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF64B5F6).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.smart_toy_outlined, size: 48, color: Color(0xFF64B5F6)),
              ),
              const SizedBox(height: 20),
              const Text(
                'No GGUF Model Loaded',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a coding model (e.g. Qwen2.5-Coder-1.5B, DeepSeek-R1, SmolLM2) to start your on-device coding agent.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _agent.isLoadingModel ? null : _pickModel,
                icon: _agent.isLoadingModel
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.file_open),
                label: Text(_agent.isLoadingModel ? 'Loading Model...' : 'Select GGUF Model'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF64B5F6),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Quick Action Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _buildPresetChip('🐛 Fix division bug in calculator.dart', 'Fix the division by zero bug in lib/calculator.dart by adding validation and updating the file.'),
              _buildPresetChip('⚡ Add Matrix math in lib/matrix.dart', 'Create a new file lib/matrix.dart with a 2x2 Matrix multiplication and determinant class.'),
              _buildPresetChip('🧪 Add unit tests for DataService', 'Write unit tests in test/data_service_test.dart for the fetchUserProfile method in lib/data_service.dart.'),
              _buildPresetChip('🔍 Search workspace for cache', 'Search the workspace for any occurrences of "cache" and explain what they do.'),
            ],
          ),
        ),

        // Trajectory Feed
        Expanded(
          child: _agent.trajectory.isEmpty
              ? const Center(
                  child: Text(
                    'Ask the agent to build, refactor, inspect, or test your code.',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  controller: _trajectoryScroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _agent.trajectory.length,
                  itemBuilder: (context, idx) {
                    final step = _agent.trajectory[idx];
                    return _buildTrajectoryStepCard(step);
                  },
                ),
        ),

        // Bottom Input Area
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFF181825),
            border: Border(top: BorderSide(color: Color(0xFF28283D))),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _agent.isRunningTask ? 'Agent is working on code...' : 'Instruct coding agent (e.g. "Add unit test for ...")',
                      hintStyle: const TextStyle(fontSize: 13, color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1E1E2E),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: _agent.isRunningTask ? null : _runTask,
                  ),
                ),
                const SizedBox(width: 8),
                if (_agent.isRunningTask)
                  IconButton.filled(
                    tooltip: 'Cancel Task',
                    icon: const Icon(Icons.stop, color: Colors.white),
                    style: IconButton.styleFrom(backgroundColor: Colors.redAccent),
                    onPressed: _agent.cancelTask,
                  )
                else
                  IconButton.filled(
                    tooltip: 'Send Task',
                    icon: const Icon(Icons.send_rounded, color: Colors.black),
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFF64B5F6)),
                    onPressed: () => _runTask(_promptController.text),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, String prompt) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        backgroundColor: const Color(0xFF1E1E2E),
        side: const BorderSide(color: Color(0xFF2E2E3E)),
        onPressed: _agent.isRunningTask ? null : () => _runTask(prompt),
      ),
    );
  }

  Widget _buildTrajectoryStepCard(AgentTrajectoryStep step) {
    switch (step.type) {
      case AgentStepType.userRequest:
        return Card(
          color: const Color(0xFF1E293B),
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.person, color: Color(0xFF64B5F6), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step.content,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );

      case AgentStepType.thinking:
        return Card(
          color: const Color(0xFF181825),
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF28283D)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFB74D)),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Thinking & Analyzing...',
                      style: TextStyle(fontSize: 11, color: Color(0xFFFFB74D), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (step.content.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    step.content,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        );

      case AgentStepType.toolExecuting:
      case AgentStepType.toolExecuted:
        final invocation = step.toolInvocation;
        final isExecuting = step.type == AgentStepType.toolExecuting;

        return Card(
          color: const Color(0xFF161F2E),
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isExecuting ? const Color(0xFF64B5F6) : const Color(0xFF81C784).withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isExecuting ? Icons.settings : Icons.check_circle_outline,
                      color: isExecuting ? const Color(0xFF64B5F6) : const Color(0xFF81C784),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tool: ${invocation?.toolName ?? "tool"}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isExecuting ? const Color(0xFF64B5F6) : const Color(0xFF81C784),
                      ),
                    ),
                    const Spacer(),
                    if (isExecuting)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF64B5F6)),
                      ),
                  ],
                ),
                if (invocation?.arguments.isNotEmpty ?? false) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      invocation!.arguments.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70),
                    ),
                  ),
                ],
                if (step.toolOutput != null) ...[
                  const SizedBox(height: 8),
                  const Text('Observation:', style: TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A101D),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      step.toolOutput!,
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF81C784)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

      case AgentStepType.finalAnswer:
        return Card(
          color: const Color(0xFF1E2E20),
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF81C784)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.task_alt, color: Color(0xFF81C784), size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Solution Complete',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF81C784)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  step.content,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
              ],
            ),
          ),
        );

      case AgentStepType.error:
        return Card(
          color: const Color(0xFF2E1616),
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.redAccent),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(step.content, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
          ),
        );
    }
  }

  // ================= TAB 2: WORKSPACE & DIFF EXPLORER =================
  Widget _buildWorkspaceTab() {
    final selectedFile = _selectedFilePath != null ? _workspace.files[_selectedFilePath] : null;

    return Column(
      children: [
        if (_workspace.diskDirectoryPath != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF1E2230),
            child: Row(
              children: [
                const Icon(Icons.sd_storage, size: 14, color: Color(0xFF81C784)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Visible Storage: ${_workspace.diskDirectoryPath}',
                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF81C784)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 12, color: Colors.white60),
                  tooltip: 'Copy Directory Path',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _workspace.diskDirectoryPath!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Storage path copied!'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: Row(
            children: [
              // Left File Tree (140 width)
              Container(
                width: 140,
                decoration: const BoxDecoration(
                  color: Color(0xFF181825),
                  border: Border(right: BorderSide(color: Color(0xFF28283D))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(Icons.folder, size: 16, color: Color(0xFF64B5F6)),
                          const SizedBox(width: 6),
                          const Text('Files', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 14),
                            tooltip: 'Reset Workspace',
                            onPressed: () {
                              _workspace.resetToDefault();
                              setState(() => _selectedFilePath = _workspace.filePaths.firstOrNull);
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFF28283D)),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _workspace.filePaths.length,
                        itemBuilder: (context, idx) {
                          final path = _workspace.filePaths[idx];
                          final file = _workspace.files[path];
                          final isSelected = path == _selectedFilePath;

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            selected: isSelected,
                            selectedTileColor: const Color(0xFF64B5F6).withValues(alpha: 0.15),
                            leading: Icon(
                              path.endsWith('.dart') ? Icons.code : Icons.description,
                              size: 14,
                              color: file?.isModifiedByAgent == true
                                  ? const Color(0xFFFFB74D)
                                  : file?.isCreatedByAgent == true
                                      ? const Color(0xFF81C784)
                                      : Colors.white60,
                            ),
                            title: Text(
                              path,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? const Color(0xFF64B5F6) : Colors.white70,
                              ),
                            ),
                            subtitle: (file != null && (file.additionsCount > 0 || file.deletionsCount > 0))
                                ? Row(
                                    children: [
                                      if (file.additionsCount > 0)
                                        Text('+${file.additionsCount} ', style: const TextStyle(fontSize: 9, color: Color(0xFF81C784), fontWeight: FontWeight.bold)),
                                      if (file.deletionsCount > 0)
                                        Text('-${file.deletionsCount}', style: const TextStyle(fontSize: 9, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                    ],
                                  )
                                : null,
                            onTap: () => setState(() => _selectedFilePath = path),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Right Code & Diff Viewer
              Expanded(
                child: selectedFile == null
                    ? const Center(child: Text('Select a file to inspect code.', style: TextStyle(color: Colors.white38)))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            color: const Color(0xFF181825),
                            child: Row(
                              children: [
                                Text(
                                  selectedFile.path,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                if (selectedFile.isCreatedByAgent)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF81C784).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Created', style: TextStyle(fontSize: 9, color: Color(0xFF81C784))),
                                  )
                                else if (selectedFile.isModifiedByAgent)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFB74D).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Modified', style: TextStyle(fontSize: 9, color: Color(0xFFFFB74D))),
                                  ),
                                const Spacer(),
                                if (selectedFile.diffLines.isNotEmpty)
                                  SegmentedButton<bool>(
                                    segments: const [
                                      ButtonSegment(value: false, label: Text('Code', style: TextStyle(fontSize: 10))),
                                      ButtonSegment(value: true, label: Text('Diff ±', style: TextStyle(fontSize: 10))),
                                    ],
                                    selected: {_showDiffView},
                                    onSelectionChanged: (s) => setState(() => _showDiffView = s.first),
                                    style: SegmentedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 14),
                                  tooltip: 'Copy Code',
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: selectedFile.content));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Code copied to clipboard!'), duration: Duration(seconds: 1)),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFF28283D)),
                          Expanded(
                            child: _showDiffView && selectedFile.diffLines.isNotEmpty
                                ? _buildDiffView(selectedFile)
                                : _buildCodeView(selectedFile),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCodeView(WorkspaceFile file) {
    final lines = file.content.split('\n');
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: lines.length,
      itemBuilder: (context, idx) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${idx + 1}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white24),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                lines[idx],
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFFE0E0E0)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDiffView(WorkspaceFile file) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: file.diffLines.length,
      itemBuilder: (context, idx) {
        final diff = file.diffLines[idx];
        Color bg = Colors.transparent;
        Color fg = const Color(0xFFE0E0E0);
        String prefix = ' ';

        if (diff.type == DiffType.insertion) {
          bg = const Color(0xFF1E3A2B);
          fg = const Color(0xFFA7F3D0);
          prefix = '+';
        } else if (diff.type == DiffType.deletion) {
          bg = const Color(0xFF3B1E22);
          fg = const Color(0xFFFCA5A5);
          prefix = '-';
        }

        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  diff.newLineNumber?.toString() ?? diff.oldLineNumber?.toString() ?? '',
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white30),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 16,
                child: Text(
                  prefix,
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: fg),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: SelectableText(
                  diff.text,
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ================= TAB 3: SETTINGS =================
  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Agent & Sampling Configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Temperature'),
          subtitle: Text(_temperature.toStringAsFixed(2)),
          trailing: SizedBox(
            width: 150,
            child: Slider(
              value: _temperature,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (v) => setState(() => _temperature = v),
            ),
          ),
        ),
        ListTile(
          title: const Text('Top-P'),
          subtitle: Text(_topP.toStringAsFixed(2)),
          trailing: SizedBox(
            width: 150,
            child: Slider(
              value: _topP,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              onChanged: (v) => setState(() => _topP = v),
            ),
          ),
        ),
        ListTile(
          title: const Text('CPU Threads'),
          subtitle: Text('$_nThreads threads'),
          trailing: DropdownButton<int>(
            value: _nThreads,
            items: [2, 4, 6, 8].map((t) => DropdownMenuItem(value: t, child: Text('$t'))).toList(),
            onChanged: (v) => setState(() => _nThreads = v ?? 4),
          ),
        ),
        ListTile(
          title: const Text('Context Window (nCtx)'),
          subtitle: Text('$_nCtx tokens'),
          trailing: DropdownButton<int>(
            value: _nCtx,
            items: [2048, 4096, 8192].map((c) => DropdownMenuItem(value: c, child: Text('$c'))).toList(),
            onChanged: (v) => setState(() => _nCtx = v ?? 4096),
          ),
        ),
        ListTile(
          title: const Text('Max Agent Steps'),
          subtitle: Text('$_maxSteps iterations'),
          trailing: DropdownButton<int>(
            value: _maxSteps,
            items: [4, 8, 12, 16].map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
            onChanged: (v) => setState(() => _maxSteps = v ?? 8),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _agent.clearTrajectory,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear Agent Trajectory'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E1E2E)),
        ),
      ],
    );
  }
}
