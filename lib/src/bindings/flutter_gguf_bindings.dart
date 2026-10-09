import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Opaque context struct
final class FlutterGgufContext extends Opaque {}

// C function signatures
typedef BackendInitC = Void Function();
typedef BackendInitDart = void Function();

typedef LoadModelC = Pointer<FlutterGgufContext> Function(
  Pointer<Utf8> modelPath,
  Int32 nCtx,
  Int32 nThreads,
  Int32 nGpuLayers,
);
typedef LoadModelDart = Pointer<FlutterGgufContext> Function(
  Pointer<Utf8> modelPath,
  int nCtx,
  int nThreads,
  int nGpuLayers,
);

typedef TokenizeC = Int32 Function(
  Pointer<FlutterGgufContext> ctx,
  Pointer<Utf8> text,
  Pointer<Int32> outTokens,
  Int32 maxTokens,
  Bool addSpecial,
  Bool parseSpecial,
);
typedef TokenizeDart = int Function(
  Pointer<FlutterGgufContext> ctx,
  Pointer<Utf8> text,
  Pointer<Int32> outTokens,
  int maxTokens,
  bool addSpecial,
  bool parseSpecial,
);

typedef PreparePromptC = Int32 Function(
  Pointer<FlutterGgufContext> ctx,
  Pointer<Utf8> prompt,
  Float temperature,
  Float topP,
  Int32 topK,
  Float penaltyRepeat,
  Float penaltyFreq,
  Float penaltyPresent,
  Uint32 seed,
);
typedef PreparePromptDart = int Function(
  Pointer<FlutterGgufContext> ctx,
  Pointer<Utf8> prompt,
  double temperature,
  double topP,
  int topK,
  double penaltyRepeat,
  double penaltyFreq,
  double penaltyPresent,
  int seed,
);

typedef StepTokenC = Int32 Function(
  Pointer<FlutterGgufContext> ctx,
  Pointer<Utf8> outPiece,
  Int32 outPieceSize,
  Pointer<Int32> outTokenId,
  Pointer<Bool> isEog,
);
typedef StepTokenDart = int Function(
  Pointer<FlutterGgufContext> ctx,
  Pointer<Utf8> outPiece,
  int outPieceSize,
  Pointer<Int32> outTokenId,
  Pointer<Bool> isEog,
);

typedef StopGenerationC = Void Function(Pointer<FlutterGgufContext> ctx);
typedef StopGenerationDart = void Function(Pointer<FlutterGgufContext> ctx);

typedef ApplyChatTemplateC = Int32 Function(
  Pointer<FlutterGgufContext> ctx,
  Pointer<Pointer<Utf8>> roles,
  Pointer<Pointer<Utf8>> contents,
  Int32 nMsg,
  Bool addAss,
  Pointer<Utf8> outBuf,
  Int32 bufSize,
);
typedef ApplyChatTemplateDart = int Function(
  Pointer<FlutterGgufContext> ctx,
  Pointer<Pointer<Utf8>> roles,
  Pointer<Pointer<Utf8>> contents,
  int nMsg,
  bool addAss,
  Pointer<Utf8> outBuf,
  int bufSize,
);

typedef GetModelDescC = Int32 Function(
  Pointer<FlutterGgufContext> ctx,
  Pointer<Utf8> outDesc,
  Int32 descSize,
);
typedef GetModelDescDart = int Function(
  Pointer<FlutterGgufContext> ctx,
  Pointer<Utf8> outDesc,
  int descSize,
);

typedef GetNCtxTrainC = Int32 Function(Pointer<FlutterGgufContext> ctx);
typedef GetNCtxTrainDart = int Function(Pointer<FlutterGgufContext> ctx);

typedef GetNLayerC = Int32 Function(Pointer<FlutterGgufContext> ctx);
typedef GetNLayerDart = int Function(Pointer<FlutterGgufContext> ctx);

typedef FreeContextC = Void Function(Pointer<FlutterGgufContext> ctx);
typedef FreeContextDart = void Function(Pointer<FlutterGgufContext> ctx);

class FlutterGgufBindings {
  final DynamicLibrary _lib;

  late final BackendInitDart backendInit;
  late final LoadModelDart loadModel;
  late final TokenizeDart tokenize;
  late final PreparePromptDart preparePrompt;
  late final StepTokenDart stepToken;
  late final StopGenerationDart stopGeneration;
  late final ApplyChatTemplateDart applyChatTemplate;
  late final GetModelDescDart getModelDesc;
  late final GetNCtxTrainDart getNCtxTrain;
  late final GetNLayerDart getNLayer;
  late final FreeContextDart freeContext;

  FlutterGgufBindings([DynamicLibrary? lib])
      : _lib = lib ?? _openLibrary() {
    backendInit = _lib
        .lookupFunction<BackendInitC, BackendInitDart>('flutter_gguf_backend_init');
    loadModel = _lib
        .lookupFunction<LoadModelC, LoadModelDart>('flutter_gguf_load_model');
    tokenize = _lib
        .lookupFunction<TokenizeC, TokenizeDart>('flutter_gguf_tokenize');
    preparePrompt = _lib
        .lookupFunction<PreparePromptC, PreparePromptDart>('flutter_gguf_prepare_prompt');
    stepToken = _lib
        .lookupFunction<StepTokenC, StepTokenDart>('flutter_gguf_step_token');
    stopGeneration = _lib
        .lookupFunction<StopGenerationC, StopGenerationDart>('flutter_gguf_stop_generation');
    applyChatTemplate = _lib
        .lookupFunction<ApplyChatTemplateC, ApplyChatTemplateDart>('flutter_gguf_apply_chat_template');
    getModelDesc = _lib
        .lookupFunction<GetModelDescC, GetModelDescDart>('flutter_gguf_get_model_desc');
    getNCtxTrain = _lib
        .lookupFunction<GetNCtxTrainC, GetNCtxTrainDart>('flutter_gguf_get_n_ctx_train');
    getNLayer = _lib
        .lookupFunction<GetNLayerC, GetNLayerDart>('flutter_gguf_get_n_layer');
    freeContext = _lib
        .lookupFunction<FreeContextC, FreeContextDart>('flutter_gguf_free_context');
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libflutter_gguf_plugin.so');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libflutter_gguf_plugin.so');
    } else if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('flutter_gguf_plugin.dll');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}
