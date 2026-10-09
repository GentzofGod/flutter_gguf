import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gguf_example/main.dart';

void main() {
  testWidgets('Renders GGUF Mobile Runner UI', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GgufRunnerHomePage(),
    ));

    expect(find.text('Flutter GGUF Mobile Runner'), findsOneWidget);
    expect(find.text('GGUF Model File Path'), findsOneWidget);
    expect(find.text('On-Device GGUF Inference'), findsOneWidget);
  });
}
