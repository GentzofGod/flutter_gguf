/// Configuration parameters for loading a GGUF model.
class ModelParams {
  /// Context size (number of tokens). Default: 2048.
  final int contextSize;

  /// Number of CPU threads to use for inference. Default: 4.
  final int threads;

  /// Number of layers to offload to GPU (Vulkan/OpenCL if enabled). Default: 0.
  final int gpuLayers;

  const ModelParams({
    this.contextSize = 2048,
    this.threads = 4,
    this.gpuLayers = 0,
  });

  ModelParams copyWith({
    int? contextSize,
    int? threads,
    int? gpuLayers,
  }) {
    return ModelParams(
      contextSize: contextSize ?? this.contextSize,
      threads: threads ?? this.threads,
      gpuLayers: gpuLayers ?? this.gpuLayers,
    );
  }
}

/// Sampling parameters for token generation.
class SamplingParams {
  /// Temperature for sampling. 0.0 = greedy (deterministic). Default: 0.7.
  final double temperature;

  /// Top-p (nucleus) sampling probability threshold. Default: 0.9.
  final double topP;

  /// Top-k sampling limit. Default: 40.
  final int topK;

  /// Repetition penalty. 1.0 = disabled. Default: 1.1.
  final double penaltyRepeat;

  /// Frequency penalty. Default: 0.0.
  final double penaltyFreq;

  /// Presence penalty. Default: 0.0.
  final double penaltyPresent;

  /// Maximum tokens to generate. Default: 512.
  final int maxTokens;

  /// Random seed. 0 = random.
  final int seed;

  const SamplingParams({
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.penaltyRepeat = 1.1,
    this.penaltyFreq = 0.0,
    this.penaltyPresent = 0.0,
    this.maxTokens = 512,
    this.seed = 0,
  });

  SamplingParams copyWith({
    double? temperature,
    double? topP,
    int? topK,
    double? penaltyRepeat,
    double? penaltyFreq,
    double? penaltyPresent,
    int? maxTokens,
    int? seed,
  }) {
    return SamplingParams(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      penaltyRepeat: penaltyRepeat ?? this.penaltyRepeat,
      penaltyFreq: penaltyFreq ?? this.penaltyFreq,
      penaltyPresent: penaltyPresent ?? this.penaltyPresent,
      maxTokens: maxTokens ?? this.maxTokens,
      seed: seed ?? this.seed,
    );
  }
}

/// Message for chat templating.
class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({
    required this.role,
    required this.content,
  });

  factory ChatMessage.system(String content) =>
      ChatMessage(role: 'system', content: content);

  factory ChatMessage.user(String content) =>
      ChatMessage(role: 'user', content: content);

  factory ChatMessage.assistant(String content) =>
      ChatMessage(role: 'assistant', content: content);

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// Metadata and architecture details about a loaded model.
class ModelInfo {
  final String description;
  final int trainContextSize;
  final int layerCount;

  const ModelInfo({
    required this.description,
    required this.trainContextSize,
    required this.layerCount,
  });

  @override
  String toString() =>
      'ModelInfo(description: $description, trainContextSize: $trainContextSize, layers: $layerCount)';
}

/// Real-time performance and generation metrics.
class GenerationStats {
  final int promptTokens;
  final int generatedTokens;
  final Duration promptEvalDuration;
  final Duration generationDuration;

  const GenerationStats({
    required this.promptTokens,
    required this.generatedTokens,
    required this.promptEvalDuration,
    required this.generationDuration,
  });

  double get tokensPerSecond {
    final secs = generationDuration.inMicroseconds / 1000000.0;
    if (secs <= 0 || generatedTokens <= 0) return 0.0;
    return generatedTokens / secs;
  }

  @override
  String toString() =>
      '${tokensPerSecond.toStringAsFixed(1)} tokens/sec ($generatedTokens tokens in ${generationDuration.inMilliseconds}ms)';
}
