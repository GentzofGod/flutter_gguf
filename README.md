# flutter_gguf

A high-performance Flutter plugin for running **GGUF (llama.cpp)** language models directly and offline on Android devices via **Dart FFI** and background **Dart Isolates**.

---

## Features

- **On-Device & 100% Offline**: Run quantized GGUF models directly on mobile without internet access.
- **High-Performance Native C++ Engine**: Powered by `llama.cpp` with ARM NEON, FP16 arithmetic, and Dot Product optimizations.
- **Non-Blocking UI (Dart Isolate)**: Model loading, prompt evaluation, and token generation run on background isolates, keeping the Flutter UI fluid at 60/120 fps.
- **Token Streaming**: Stream generated tokens in real-time as a standard Dart `Stream<String>`.
- **Built-in Chat Templates**: Automatic template formatting for ChatML, Llama-3, Mistral, Gemma, and custom templates.
- **Real-Time Telemetry**: Track generation speed (tokens/sec), duration, and prompt evaluation latency.
- **Immediate Cancellation**: Stop active token generation at any point.

---

## Getting Started

### 1. Add Dependency

In your `pubspec.yaml`:

```yaml
dependencies:
  flutter_gguf: ^0.1.0
```

### 2. Android Requirements

- **Minimum SDK**: Android 7.0 (API level 24)+
- **Supported ABIs**: `arm64-v8a`, `armeabi-v7a`, `x86_64`
- **Recommended Models**: 0.5B to 3B parameter models quantized with `Q4_K_M`, `Q4_0`, `Q3_K_S`, or `Q8_0` (e.g. SmolLM2, Qwen 2.5, TinyLlama, Gemma 2 2B).

---

## Usage

### 1. Load a Model

```dart
import 'package:flutter_gguf/flutter_gguf.dart';

// Load model from device storage
final model = await LlamaModel.load(
  '/sdcard/Download/tinyllama-1.1b-chat.Q4_K_M.gguf',
  params: const ModelParams(
    contextSize: 2048, // Token context window
    threads: 4,        // CPU thread count
    gpuLayers: 0,      // GPU layer offload (0 = CPU only)
  ),
);

print('Loaded: ${model.info.description}');
print('Trained Context: ${model.info.trainContextSize}');
print('Layers: ${model.info.layerCount}');
```

### 2. Multi-Turn Chat with Streaming

```dart
final messages = [
  ChatMessage.system('You are a helpful and concise mobile AI assistant.'),
  ChatMessage.user('Explain how airplanes fly in two sentences.'),
];

// Stream response tokens
model.chat(
  messages,
  params: const SamplingParams(
    temperature: 0.7,
    topP: 0.9,
    topK: 40,
    penaltyRepeat: 1.1,
    maxTokens: 256,
  ),
  onStats: (stats) {
    print('Speed: ${stats.tokensPerSecond.toStringAsFixed(1)} tok/s');
    print('Tokens generated: ${stats.generatedTokens}');
  },
).listen((token) {
  stdout.write(token);
});
```

### 3. Raw Prompt Completion

```dart
model.generate(
  '### Instruction:\nWrite a haiku about Flutter.\n\n### Response:\n',
  params: const SamplingParams(temperature: 0.8),
).listen((piece) {
  stdout.write(piece);
});
```

### 4. Stop Active Generation

```dart
// Stops the generation loop immediately on the native side
model.stop();
```

### 5. Dispose Model

```dart
// Free native C++ llama memory and terminate background isolate
await model.dispose();
```

---

## Configuration Reference

### `ModelParams`

| Parameter | Type | Default | Description |
|---|---|---|---|
| `contextSize` | `int` | `2048` | Maximum token context window size. |
| `threads` | `int` | `4` | Number of CPU threads to use for inference. |
| `gpuLayers` | `int` | `0` | Number of layers to offload to GPU if supported. |

### `SamplingParams`

| Parameter | Type | Default | Description |
|---|---|---|---|
| `temperature` | `double` | `0.7` | Sampling randomness (`0.0` = greedy/deterministic). |
| `topP` | `double` | `0.9` | Nucleus sampling probability threshold. |
| `topK` | `int` | `40` | Top-K sampling token limit. |
| `penaltyRepeat` | `double` | `1.1` | Repetition penalty factor (`1.0` = disabled). |
| `penaltyFreq` | `double` | `0.0` | Frequency penalty. |
| `penaltyPresent` | `double` | `0.0` | Presence penalty. |
| `maxTokens` | `int` | `512` | Maximum number of new tokens to generate. |
| `seed` | `int` | `0` | Random seed (`0` = random seed). |

---

## Example App

Check out the `example/` directory for a complete Material 3 mobile application featuring:
- **Native File Picker**: Tap the folder icon to browse and select any `.gguf` model file on device storage
- **Live Token Streaming**: Real-time response generation in a responsive chat view
- **Performance Telemetry**: Live tokens/second counter and execution latency tracking
- **Runtime Inference Settings**: Adjust CPU threads, context window, temperature, top-p, and top-k on the fly

To run the example app on your connected Android device:

```bash
cd example
flutter run
```

---

## License

MIT License. Contains `llama.cpp` licensed under the MIT License.
