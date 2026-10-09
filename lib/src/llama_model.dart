import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'bindings/flutter_gguf_bindings.dart';
import 'llama_params.dart';

/// General Flutter GGUF platform utilities.
class FlutterGguf {
  static const MethodChannel _channel = MethodChannel('flutter_gguf');

  /// Pick a GGUF model file on Android with zero memory copying (built for large 500MB-4GB models).
  static Future<String?> pickModelFile() async {
    try {
      final String? path = await _channel.invokeMethod<String>('pickGgufFile');
      return path;
    } catch (e) {
      return null;
    }
  }
}

/// Commands sent to the background isolate
sealed class _WorkerCommand {}

class _LoadModelCommand extends _WorkerCommand {
  final String modelPath;
  final ModelParams params;
  final SendPort replyPort;

  _LoadModelCommand(this.modelPath, this.params, this.replyPort);
}

class _GenerateCommand extends _WorkerCommand {
  final String prompt;
  final SamplingParams params;
  final SendPort tokenPort;

  _GenerateCommand(this.prompt, this.params, this.tokenPort);
}

class _ApplyChatTemplateCommand extends _WorkerCommand {
  final List<ChatMessage> messages;
  final bool addAssistant;
  final SendPort replyPort;

  _ApplyChatTemplateCommand(this.messages, this.addAssistant, this.replyPort);
}

class _TokenizeCommand extends _WorkerCommand {
  final String text;
  final bool addSpecial;
  final bool parseSpecial;
  final SendPort replyPort;

  _TokenizeCommand(this.text, this.addSpecial, this.parseSpecial, this.replyPort);
}

class _StopCommand extends _WorkerCommand {}

class _DisposeCommand extends _WorkerCommand {
  final SendPort replyPort;

  _DisposeCommand(this.replyPort);
}

/// Token streaming events from isolate
sealed class _WorkerEvent {}

class _TokenEvent extends _WorkerEvent {
  final String piece;
  final int tokenId;

  _TokenEvent(this.piece, this.tokenId);
}

class _DoneEvent extends _WorkerEvent {
  final GenerationStats stats;

  _DoneEvent(this.stats);
}

class _ErrorEvent extends _WorkerEvent {
  final String error;

  _ErrorEvent(this.error);
}

/// Main class to interact with a GGUF model asynchronously on a background isolate.
class LlamaModel {
  final SendPort _commandPort;
  final Isolate _isolate;
  final ModelInfo info;

  bool _isDisposed = false;

  LlamaModel._({
    required this._commandPort,
    required this._isolate,
    required this.info,
  });

  /// Load a GGUF model file on a background isolate.
  static Future<LlamaModel> load(
    String modelPath, {
    ModelParams params = const ModelParams(),
  }) async {
    final initPort = ReceivePort();
    final isolate = await Isolate.spawn<_InitPayload>(
      _workerIsolateEntryPoint,
      _InitPayload(initPort.sendPort),
    );

    final commandPort = await initPort.first as SendPort;
    final responsePort = ReceivePort();

    commandPort.send(_LoadModelCommand(modelPath, params, responsePort.sendPort));

    final result = await responsePort.first;
    if (result is ModelInfo) {
      return LlamaModel._(
        commandPort: commandPort,
        isolate: isolate,
        info: result,
      );
    } else {
      isolate.kill(priority: Isolate.immediate);
      throw Exception(result is String ? result : 'Failed to load model from $modelPath');
    }
  }

  /// Generate text tokens as a stream from a prompt.
  Stream<String> generate(
    String prompt, {
    SamplingParams params = const SamplingParams(),
    void Function(GenerationStats stats)? onStats,
  }) {
    if (_isDisposed) {
      throw StateError('LlamaModel is disposed');
    }

    final controller = StreamController<String>();
    final tokenPort = ReceivePort();

    _commandPort.send(_GenerateCommand(prompt, params, tokenPort.sendPort));

    StreamSubscription? sub;
    sub = tokenPort.listen((event) {
      if (event is _TokenEvent) {
        if (!controller.isClosed) {
          controller.add(event.piece);
        }
      } else if (event is _DoneEvent) {
        onStats?.call(event.stats);
        sub?.cancel();
        tokenPort.close();
        if (!controller.isClosed) {
          controller.close();
        }
      } else if (event is _ErrorEvent) {
        sub?.cancel();
        tokenPort.close();
        if (!controller.isClosed) {
          controller.addError(Exception(event.error));
          controller.close();
        }
      }
    });

    controller.onCancel = () {
      stop();
      sub?.cancel();
      tokenPort.close();
    };

    return controller.stream;
  }

  /// Format chat messages using the model's chat template and stream assistant response.
  Stream<String> chat(
    List<ChatMessage> messages, {
    SamplingParams params = const SamplingParams(),
    void Function(GenerationStats stats)? onStats,
  }) async* {
    final formattedPrompt = await applyChatTemplate(messages, addAssistant: true);
    yield* generate(formattedPrompt, params: params, onStats: onStats);
  }

  /// Apply the model's built-in chat template (e.g. ChatML, Llama-3, Gemma) to chat messages.
  Future<String> applyChatTemplate(
    List<ChatMessage> messages, {
    bool addAssistant = true,
  }) async {
    if (_isDisposed) throw StateError('LlamaModel is disposed');
    final responsePort = ReceivePort();
    _commandPort.send(_ApplyChatTemplateCommand(messages, addAssistant, responsePort.sendPort));
    final res = await responsePort.first;
    if (res is String) {
      return res;
    } else {
      throw Exception('Failed to apply chat template');
    }
  }

  /// Tokenize text into token IDs.
  Future<List<int>> tokenize(
    String text, {
    bool addSpecial = true,
    bool parseSpecial = true,
  }) async {
    if (_isDisposed) throw StateError('LlamaModel is disposed');
    final responsePort = ReceivePort();
    _commandPort.send(_TokenizeCommand(text, addSpecial, parseSpecial, responsePort.sendPort));
    final res = await responsePort.first;
    if (res is List<int>) {
      return res;
    } else {
      throw Exception('Failed to tokenize text');
    }
  }

  /// Request active generation to stop immediately.
  void stop() {
    if (!_isDisposed) {
      _commandPort.send(_StopCommand());
    }
  }

  /// Release model resources, free native memory, and terminate background isolate.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    final responsePort = ReceivePort();
    _commandPort.send(_DisposeCommand(responsePort.sendPort));
    await responsePort.first;

    _isolate.kill(priority: Isolate.immediate);
  }
}

class _InitPayload {
  final SendPort sendPort;
  _InitPayload(this.sendPort);
}

/// Entry point running in the background Dart Isolate
void _workerIsolateEntryPoint(_InitPayload payload) {
  final commandPort = ReceivePort();
  payload.sendPort.send(commandPort.sendPort);

  final bindings = FlutterGgufBindings();
  Pointer<FlutterGgufContext>? ctx;

  commandPort.listen((message) {
    if (message is _LoadModelCommand) {
      try {
        final pathPtr = message.modelPath.toNativeUtf8();
        ctx = bindings.loadModel(
          pathPtr,
          message.params.contextSize,
          message.params.threads,
          message.params.gpuLayers,
        );
        malloc.free(pathPtr);

        if (ctx == null || ctx == nullptr) {
          message.replyPort.send('Native llama_model_load returned NULL for ${message.modelPath}');
          return;
        }

        // Retrieve model info
        final descBuf = malloc<Uint8>(512).cast<Utf8>();
        bindings.getModelDesc(ctx!, descBuf, 512);
        final descStr = descBuf.toDartString();
        malloc.free(descBuf);

        final nCtxTrain = bindings.getNCtxTrain(ctx!);
        final nLayer = bindings.getNLayer(ctx!);

        final info = ModelInfo(
          description: descStr.isNotEmpty ? descStr : 'GGUF Model',
          trainContextSize: nCtxTrain,
          layerCount: nLayer,
        );

        message.replyPort.send(info);
      } catch (e) {
        message.replyPort.send('Exception loading model: $e');
      }
    } else if (message is _GenerateCommand) {
      if (ctx == null || ctx == nullptr) {
        message.tokenPort.send(_ErrorEvent('Model context is not initialized'));
        return;
      }

      try {
        final promptStopwatch = Stopwatch()..start();
        final promptPtr = message.prompt.toNativeUtf8();

        final prepRet = bindings.preparePrompt(
          ctx!,
          promptPtr,
          message.params.temperature,
          message.params.topP,
          message.params.topK,
          message.params.penaltyRepeat,
          message.params.penaltyFreq,
          message.params.penaltyPresent,
          message.params.seed,
        );
        malloc.free(promptPtr);
        promptStopwatch.stop();

        if (prepRet != 0) {
          message.tokenPort.send(_ErrorEvent('Failed to prepare prompt (error code $prepRet)'));
          return;
        }

        final genStopwatch = Stopwatch()..start();
        final pieceBuf = malloc<Uint8>(512).cast<Utf8>();
        final tokenIdPtr = malloc<Int32>();
        final isEogPtr = malloc<Bool>();

        int tokensGenerated = 0;
        final maxTokens = message.params.maxTokens;
        final pendingBytes = <int>[];

        while (tokensGenerated < maxTokens) {
          final pieceLen = bindings.stepToken(
            ctx!,
            pieceBuf,
            512,
            tokenIdPtr,
            isEogPtr,
          );

          if (isEogPtr.value) {
            break;
          }

          if (pieceLen > 0) {
            final u8Pointer = pieceBuf.cast<Uint8>();
            for (int i = 0; i < pieceLen; i++) {
              pendingBytes.add(u8Pointer[i]);
            }

            try {
              final decoded = utf8.decode(pendingBytes);
              message.tokenPort.send(_TokenEvent(decoded, tokenIdPtr.value));
              pendingBytes.clear();
            } catch (_) {
              // Partial multi-byte UTF-8 character, wait for subsequent token bytes
            }
            tokensGenerated++;
          }
        }

        if (pendingBytes.isNotEmpty) {
          try {
            final decoded = utf8.decode(pendingBytes, allowMalformed: true);
            if (decoded.isNotEmpty) {
              message.tokenPort.send(_TokenEvent(decoded, -1));
            }
          } catch (_) {}
          pendingBytes.clear();
        }

        malloc.free(pieceBuf);
        malloc.free(tokenIdPtr);
        malloc.free(isEogPtr);
        genStopwatch.stop();

        final stats = GenerationStats(
          promptTokens: 0,
          generatedTokens: tokensGenerated,
          promptEvalDuration: promptStopwatch.elapsed,
          generationDuration: genStopwatch.elapsed,
        );

        message.tokenPort.send(_DoneEvent(stats));
      } catch (e) {
        message.tokenPort.send(_ErrorEvent('Generation error: $e'));
      }
    } else if (message is _ApplyChatTemplateCommand) {
      if (ctx == null || ctx == nullptr) {
        message.replyPort.send('');
        return;
      }

      try {
        final nMsg = message.messages.length;
        final rolesPtr = malloc<Pointer<Utf8>>(nMsg);
        final contentsPtr = malloc<Pointer<Utf8>>(nMsg);

        for (int i = 0; i < nMsg; i++) {
          rolesPtr[i] = message.messages[i].role.toNativeUtf8();
          contentsPtr[i] = message.messages[i].content.toNativeUtf8();
        }

        int bufSize = 4096;
        var outBuf = malloc<Uint8>(bufSize).cast<Utf8>();
        var ret = bindings.applyChatTemplate(
          ctx!,
          rolesPtr,
          contentsPtr,
          nMsg,
          message.addAssistant,
          outBuf,
          bufSize,
        );

        if (ret > bufSize) {
          malloc.free(outBuf);
          bufSize = ret + 256;
          outBuf = malloc<Uint8>(bufSize).cast<Utf8>();
          ret = bindings.applyChatTemplate(
            ctx!,
            rolesPtr,
            contentsPtr,
            nMsg,
            message.addAssistant,
            outBuf,
            bufSize,
          );
        }

        String result = '';
        if (ret > 0) {
          result = outBuf.toDartString();
        } else {
          // Fallback simple ChatML formatting if template not found in GGUF metadata
          final buffer = StringBuffer();
          for (final msg in message.messages) {
            buffer.write('<|im_start|>${msg.role}\n${msg.content}<|im_end|>\n');
          }
          if (message.addAssistant) {
            buffer.write('<|im_start|>assistant\n');
          }
          result = buffer.toString();
        }

        malloc.free(outBuf);
        for (int i = 0; i < nMsg; i++) {
          malloc.free(rolesPtr[i]);
          malloc.free(contentsPtr[i]);
        }
        malloc.free(rolesPtr);
        malloc.free(contentsPtr);

        message.replyPort.send(result);
      } catch (e) {
        message.replyPort.send('');
      }
    } else if (message is _TokenizeCommand) {
      if (ctx == null || ctx == nullptr) {
        message.replyPort.send(<int>[]);
        return;
      }

      try {
        final textPtr = message.text.toNativeUtf8();
        int maxTokens = message.text.length + 128;
        var outTokens = malloc<Int32>(maxTokens);

        var nTokens = bindings.tokenize(
          ctx!,
          textPtr,
          outTokens,
          maxTokens,
          message.addSpecial,
          message.parseSpecial,
        );

        if (nTokens < 0) {
          malloc.free(outTokens);
          maxTokens = -nTokens;
          outTokens = malloc<Int32>(maxTokens);
          nTokens = bindings.tokenize(
            ctx!,
            textPtr,
            outTokens,
            maxTokens,
            message.addSpecial,
            message.parseSpecial,
          );
        }

        final tokens = <int>[];
        if (nTokens > 0) {
          for (int i = 0; i < nTokens; i++) {
            tokens.add(outTokens[i]);
          }
        }

        malloc.free(textPtr);
        malloc.free(outTokens);

        message.replyPort.send(tokens);
      } catch (e) {
        message.replyPort.send(<int>[]);
      }
    } else if (message is _StopCommand) {
      if (ctx != null && ctx != nullptr) {
        bindings.stopGeneration(ctx!);
      }
    } else if (message is _DisposeCommand) {
      if (ctx != null && ctx != nullptr) {
        bindings.freeContext(ctx!);
        ctx = null;
      }
      message.replyPort.send(true);
    }
  });
}
