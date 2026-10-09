## 0.1.0

* Initial release of `flutter_gguf`.
* On-device GGUF LLM inference powered by native C++ `llama.cpp`.
* Dart FFI zero-overhead bindings.
* Non-blocking background Dart Isolate architecture for token generation.
* Real-time token streaming API (`Stream<String>`).
* Built-in chat template support (ChatML, Llama-3, Gemma, Mistral).
* Parameter tuning for context size, CPU threads, temperature, top-p, top-k, repetition penalty, and max tokens.
* Zero-copy native Android file picker for large model files.
* Android NDK support with ARM NEON, FP16, and Dot Product optimizations.
