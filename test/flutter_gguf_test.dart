import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gguf/flutter_gguf.dart';

void main() {
  test('ModelParams default values', () {
    const params = ModelParams();
    expect(params.contextSize, 2048);
    expect(params.threads, 4);
    expect(params.gpuLayers, 0);

    final modified = params.copyWith(threads: 8, contextSize: 4096);
    expect(modified.threads, 8);
    expect(modified.contextSize, 4096);
  });

  test('SamplingParams default values and copyWith', () {
    const sampling = SamplingParams();
    expect(sampling.temperature, 0.7);
    expect(sampling.topP, 0.9);
    expect(sampling.topK, 40);

    final modified = sampling.copyWith(temperature: 0.2, maxTokens: 256);
    expect(modified.temperature, 0.2);
    expect(modified.maxTokens, 256);
  });

  test('ChatMessage helpers', () {
    final system = ChatMessage.system('You are a helpful assistant.');
    final user = ChatMessage.user('Hello');
    final assistant = ChatMessage.assistant('Hi there!');

    expect(system.role, 'system');
    expect(user.role, 'user');
    expect(assistant.role, 'assistant');
    expect(user.content, 'Hello');
  });
}
