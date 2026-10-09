# flutter_gguf_example

A showcase application demonstrating on-device LLM inference using the `flutter_gguf` plugin.

## Features Demonstrated

- 💬 **Interactive Chat Interface**: Material 3 chat with markdown-like message bubbles and user/assistant state tracking.
- ⚡ **Zero-Copy Model Picker**: Select GGUF models directly from storage without copying multi-gigabyte files into JVM memory.
- 🌊 **Real-Time Token Streaming**: Watch tokens generate live in the UI without freezing the main thread.
- 📊 **Telemetry HUD**: Real-time performance metrics showing tokens per second (tok/s), generation latency, and context stats.
- ⚙️ **Configurable Generation Parameters**: Adjust temperature, Top-P, Top-K, repeat penalty, thread count, and context size dynamically.
- 🛑 **Streaming Cancellation**: Cancel long generations immediately with the stop button.

---

## Recommended Models for Testing

Small quantized GGUF models (Q4_K_M or Q8_0) run efficiently on modern Android devices:

| Model | Size (Q4_K_M) | Recommended RAM | Links |
| :--- | :--- | :--- | :--- |
| **SmolLM2-135M-Instruct** | ~90 MB | 1 GB+ | [Hugging Face](https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct-GGUF) |
| **Qwen2.5-0.5B-Instruct** | ~390 MB | 2 GB+ | [Hugging Face](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF) |
| **Llama-3.2-1B-Instruct** | ~800 MB | 3 GB+ | [Hugging Face](https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF) |
| **Qwen2.5-1.5B-Instruct** | ~1.1 GB | 4 GB+ | [Hugging Face](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF) |

---

## How to Run

### 1. Download a Model to Your Device

Transfer any `.gguf` file to your Android device's **Download** or internal storage folder via USB, `adb push`, or direct download from Hugging Face in the device's browser:

```bash
adb push ~/Downloads/qwen2.5-0.5b-instruct-q4_k_m.gguf /sdcard/Download/
```

### 2. Run the App

For maximum native performance and compiler optimizations (NEON/FP16), always run the example in **Release** or **Profile** mode on a physical device:

```bash
flutter run --release
```

### 3. Select & Chat

1. Tap **"Select Model File"** on the home screen.
2. Pick your downloaded `.gguf` file using the system file picker.
3. Once loaded, type your message and enjoy private, fast, offline AI on your phone!

