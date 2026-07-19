import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'local_speech_recognizer.dart';
import 'sherpa_transducer_recognizer.dart';
import 'sherpa_whisper_recognizer.dart';

/// Picks the sherpa-onnx recognizer implementation matching the installed
/// pack's architecture. Reads `potok-model.json`'s `model_type` synchronously
/// (a few bytes, cheap) rather than widening [RecognizerFactory] to async.
///
/// Missing manifest (the `POTOK_ASR_MODEL_DIR` dev fallback has none) is
/// treated as Whisper, matching the pre-multi-engine behaviour.
LocalSpeechRecognizer createSherpaRecognizer(
  String modelDir, {
  String? nativeLibraryDir,
}) {
  final modelType = _readModelType(modelDir);
  if (modelType == 'nemo_transducer') {
    return SherpaTransducerRecognizer(
      modelDir: modelDir,
      nativeLibraryDir: nativeLibraryDir,
    );
  }
  return SherpaWhisperRecognizer(
    modelDir: modelDir,
    nativeLibraryDir: nativeLibraryDir,
  );
}

String _readModelType(String modelDir) {
  final manifestFile = File(p.join(modelDir, 'potok-model.json'));
  if (!manifestFile.existsSync()) return 'whisper';
  try {
    final decoded = json.decode(manifestFile.readAsStringSync());
    if (decoded is Map<String, Object?>) {
      final modelType = decoded['model_type'];
      if (modelType is String && modelType.isNotEmpty) return modelType;
    }
  } on FormatException {
    // Битый манифест — оставляем прежнее поведение (whisper); activate()
    // уже отказал бы установить такой пак, так что это защитный fallback.
  }
  return 'whisper';
}
