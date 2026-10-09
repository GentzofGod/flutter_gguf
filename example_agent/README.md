# flutter_gguf_agent_example

An autonomous, on-device **Mobile Coding Agent** powered by [`flutter_gguf`](https://github.com/GentzofGod/flutter_gguf).

This example demonstrates how to build an intelligent, multi-step ReAct (Reason + Act) coding agent running completely locally on mobile devices without any cloud dependencies.

---

## Features

- 🤖 **Autonomous Multi-Step ReAct Engine**: The agent thinks, invokes tools, receives observations, and refines code iteratively.
- 🛠️ **Local Workspace Tools**:
  - `read_file(path)`: Inspect source code in the workspace.
  - `write_file(path, content)`: Generate or modify code files in real-time.
  - `list_files(directory)`: Explore the workspace directory structure.
  - `search_code(query)`: Search for symbols, functions, or text across the project.
  - `analyze_syntax(path)`: Verify structural and delimiter validity.
- 📁 **Live Workspace Explorer & Code Viewer**: Inspect, copy, and observe files as the agent creates and modifies them in real time.
- 🌊 **Real-Time Token Streaming & Telemetry**: Watch reasoning and tool generation stream live with tok/s metrics.
- 🧪 **Quick Action Prompts**: One-tap scenarios to test bug fixing, feature creation, test generation, and code search.

---

## Recommended Coding Models (GGUF)

For optimal code generation on mobile:

1. **Qwen2.5-Coder-1.5B-Instruct** (Recommended) — [Download GGUF](https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF)
2. **DeepSeek-R1-Distill-Qwen-1.5B** — [Download GGUF](https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF)
3. **SmolLM2-1.7B-Instruct** — [Download GGUF](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF)

---

## How to Run

1. Transfer a `.gguf` coding model to your Android device.
2. Run in release mode:
   ```bash
   cd example_agent
   flutter run --release
   ```
3. Tap **Select GGUF Model**, pick your model, and start coding!
