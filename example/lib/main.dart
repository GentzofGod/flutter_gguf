import 'package:flutter/material.dart';
import 'package:flutter_gguf/flutter_gguf.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Flutter GGUF Android Runner',
    home: GgufRunnerHomePage(),
  ));
}

class GgufRunnerHomePage extends StatefulWidget {
  const GgufRunnerHomePage({super.key});

  @override
  State<GgufRunnerHomePage> createState() => _GgufRunnerHomePageState();
}

class _GgufRunnerHomePageState extends State<GgufRunnerHomePage> {
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _promptController = TextEditingController(
    text: 'Hello! How can you assist me today?',
  );
  final ScrollController _chatScrollController = ScrollController();

  LlamaModel? _model;
  bool _isLoadingModel = false;
  bool _isGenerating = false;
  String _streamedResponse = '';
  GenerationStats? _latestStats;
  String? _errorMessage;

  // Settings
  int _threads = 4;
  int _contextSize = 2048;
  int _gpuLayers = 0;
  double _temperature = 0.7;
  double _topP = 0.9;
  int _topK = 40;
  int _maxTokens = 256;

  final List<ChatMessage> _messages = [];

  @override
  void dispose() {
    _model?.dispose();
    _pathController.dispose();
    _promptController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickModelFile() async {
    try {
      final path = await FlutterGguf.pickModelFile();
      if (path != null && path.isNotEmpty) {
        setState(() {
          _pathController.text = path;
        });
        _showSnackbar('Selected: $path');
      }
    } catch (e) {
      _showSnackbar('Error picking file: $e');
    }
  }

  Future<void> _loadModel() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      _showSnackbar('Please enter a valid model path');
      return;
    }

    setState(() {
      _isLoadingModel = true;
      _errorMessage = null;
    });

    try {
      if (_model != null) {
        await _model!.dispose();
        _model = null;
      }

      final loadedModel = await LlamaModel.load(
        path,
        params: ModelParams(
          contextSize: _contextSize,
          threads: _threads,
          gpuLayers: _gpuLayers,
        ),
      );

      setState(() {
        _model = loadedModel;
        _isLoadingModel = false;
      });
      _showSnackbar('Model loaded successfully!');
    } catch (e) {
      setState(() {
        _isLoadingModel = false;
        _errorMessage = e.toString();
      });
      _showSnackbar('Failed to load model: $e');
    }
  }

  void _generateText() {
    if (_model == null) {
      _showSnackbar('Please load a model first');
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    final userMessage = ChatMessage.user(prompt);
    setState(() {
      _messages.add(userMessage);
      _streamedResponse = '';
      _isGenerating = true;
      _latestStats = null;
      _errorMessage = null;
    });

    _promptController.clear();
    _scrollToBottom();

    final sampling = SamplingParams(
      temperature: _temperature,
      topP: _topP,
      topK: _topK,
      maxTokens: _maxTokens,
    );

    _model!.chat(
      _messages,
      params: sampling,
      onStats: (stats) {
        setState(() {
          _latestStats = stats;
        });
      },
    ).listen(
      (token) {
        setState(() {
          _streamedResponse += token;
        });
        _scrollToBottom();
      },
      onDone: () {
        setState(() {
          if (_streamedResponse.isNotEmpty) {
            _messages.add(ChatMessage.assistant(_streamedResponse));
            _streamedResponse = '';
          }
          _isGenerating = false;
        });
        _scrollToBottom();
      },
      onError: (err) {
        setState(() {
          _isGenerating = false;
          _errorMessage = err.toString();
        });
        _showSnackbar('Generation error: $err');
      },
    );
  }

  void _stopGeneration() {
    _model?.stop();
    setState(() {
      _isGenerating = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter GGUF Mobile Runner'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Inference Settings',
            onPressed: () => _showSettingsDialog(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Model Load Bar
            _buildModelControlHeader(theme),

            // Error Banner
            if (_errorMessage != null) _buildErrorBanner(),

            // Chat Messages / Stream View
            Expanded(
              child: _messages.isEmpty && _streamedResponse.isEmpty
                  ? _buildEmptyState(theme)
                  : _buildChatList(theme),
            ),

            // Performance Stats
            if (_latestStats != null) _buildStatsBar(theme),

            // Input prompt bar
            _buildPromptInput(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildModelControlHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pathController,
                  decoration: InputDecoration(
                    labelText: 'GGUF Model File Path',
                    hintText: 'Select or paste .gguf path...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.folder_open),
                      tooltip: 'Browse files',
                      onPressed: _pickModelFile,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isLoadingModel ? null : _loadModel,
                icon: _isLoadingModel
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_model == null ? 'Load' : 'Reload'),
              ),
            ],
          ),
          if (_model != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  avatar: const Icon(Icons.memory, size: 16),
                  label: Text('Arch: ${_model!.info.description}', style: const TextStyle(fontSize: 12)),
                ),
                Chip(
                  avatar: const Icon(Icons.history_edu, size: 16),
                  label: Text('Train Ctx: ${_model!.info.trainContextSize}', style: const TextStyle(fontSize: 12)),
                ),
                Chip(
                  avatar: const Icon(Icons.layers, size: 16),
                  label: Text('Layers: ${_model!.info.layerCount}', style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatList(ThemeData theme) {
    return ListView.builder(
      controller: _chatScrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length + (_streamedResponse.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < _messages.length) {
          final msg = _messages[index];
          final isUser = msg.role == 'user';
          return Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                msg.content,
                style: TextStyle(
                  color: isUser
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        } else {
          // Streaming message
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_streamedResponse),
                  const SizedBox(height: 6),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildPromptInput(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promptController,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Enter your prompt...',
                border: InputBorder.none,
              ),
              onSubmitted: (_) {
                if (!_isGenerating) _generateText();
              },
            ),
          ),
          if (_isGenerating)
            IconButton(
              icon: const Icon(Icons.stop_circle, color: Colors.red),
              tooltip: 'Stop generation',
              onPressed: _stopGeneration,
            )
          else
            IconButton(
              icon: const Icon(Icons.send),
              tooltip: 'Send prompt',
              onPressed: _model == null ? null : _generateText,
            ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '⚡ Speed: ${_latestStats!.tokensPerSecond.toStringAsFixed(1)} tok/s',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(
            'Tokens: ${_latestStats!.generatedTokens} in ${_latestStats!.generationDuration.inMilliseconds}ms',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology, size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'On-Device GGUF Inference',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Load any quantized GGUF model (e.g. Q4_K_M, Q8_0) from storage to chat completely offline on your Android device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Explain Relativity'),
                  onPressed: () {
                    _promptController.text = 'Explain Einstein\'s theory of relativity simply.';
                  },
                ),
                ActionChip(
                  label: const Text('Write a Haiku'),
                  onPressed: () {
                    _promptController.text = 'Write a haiku about artificial intelligence.';
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      color: Colors.red.shade100,
      padding: const EdgeInsets.all(8),
      child: Text(
        _errorMessage!,
        style: TextStyle(color: Colors.red.shade900, fontSize: 12),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Inference Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text('Threads: $_threads'),
                      subtitle: Slider(
                        value: _threads.toDouble(),
                        min: 1,
                        max: 8,
                        divisions: 7,
                        label: '$_threads',
                        onChanged: (v) {
                          setDialogState(() => _threads = v.toInt());
                          setState(() {});
                        },
                      ),
                    ),
                    ListTile(
                      title: Text('Context Size: $_contextSize'),
                      subtitle: Slider(
                        value: _contextSize.toDouble(),
                        min: 512,
                        max: 4096,
                        divisions: 7,
                        label: '$_contextSize',
                        onChanged: (v) {
                          setDialogState(() => _contextSize = v.toInt());
                          setState(() {});
                        },
                      ),
                    ),
                    ListTile(
                      title: Text('GPU Layers: $_gpuLayers'),
                      subtitle: Slider(
                        value: _gpuLayers.toDouble(),
                        min: 0,
                        max: 32,
                        divisions: 32,
                        label: '$_gpuLayers',
                        onChanged: (v) {
                          setDialogState(() => _gpuLayers = v.toInt());
                          setState(() {});
                        },
                      ),
                    ),
                    ListTile(
                      title: Text('Temperature: ${_temperature.toStringAsFixed(2)}'),
                      subtitle: Slider(
                        value: _temperature,
                        min: 0.0,
                        max: 1.5,
                        divisions: 15,
                        label: _temperature.toStringAsFixed(2),
                        onChanged: (v) {
                          setDialogState(() => _temperature = v);
                          setState(() {});
                        },
                      ),
                    ),
                    ListTile(
                      title: Text('Top-P: ${_topP.toStringAsFixed(2)}'),
                      subtitle: Slider(
                        value: _topP,
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        label: _topP.toStringAsFixed(2),
                        onChanged: (v) {
                          setDialogState(() => _topP = v);
                          setState(() {});
                        },
                      ),
                    ),
                    ListTile(
                      title: Text('Top-K: $_topK'),
                      subtitle: Slider(
                        value: _topK.toDouble(),
                        min: 1,
                        max: 100,
                        divisions: 99,
                        label: '$_topK',
                        onChanged: (v) {
                          setDialogState(() => _topK = v.toInt());
                          setState(() {});
                        },
                      ),
                    ),
                    ListTile(
                      title: Text('Max Output Tokens: $_maxTokens'),
                      subtitle: Slider(
                        value: _maxTokens.toDouble(),
                        min: 32,
                        max: 1024,
                        divisions: 31,
                        label: '$_maxTokens',
                        onChanged: (v) {
                          setDialogState(() => _maxTokens = v.toInt());
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
