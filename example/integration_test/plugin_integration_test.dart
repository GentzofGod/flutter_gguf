import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gguf/flutter_gguf.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ModelParams and SamplingParams instantiation test', (WidgetTester tester) async {
    const modelParams = ModelParams(contextSize: 2048, threads: 4, gpuLayers: 0);
    const samplingParams = SamplingParams(temperature: 0.7, topP: 0.9, topK: 40);

    expect(modelParams.contextSize, 2048);
    expect(modelParams.threads, 4);
    expect(samplingParams.temperature, 0.7);
    expect(samplingParams.topP, 0.9);
  });
}
