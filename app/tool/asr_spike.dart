// WP-00 ASR spike: транскрибирует WAV-файл через sherpa-onnx whisper.
//
// dart run tool/asr_spike.dart <model_dir> <wav_path> [language]
//
// Печатает текст, длительность аудио, время обработки и RTF.
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:potok/infrastructure/asr/sherpa_whisper_recognizer.dart';

/// Console-run quirk: System32 ships an old onnxruntime.dll which wins the
/// DLL search over pub-cache. Preloading by absolute path pins the right
/// modules for the whole process (in the Flutter app the plugin's DLLs sit
/// next to the exe, so this is not needed there).
void preloadNativeLibraries() {
  if (!Platform.isWindows) return;
  final dllDir = Platform.environment['SHERPA_DLL_DIR'];
  if (dllDir == null) return;
  DynamicLibrary.open(p.join(dllDir, 'onnxruntime.dll'));
  DynamicLibrary.open(p.join(dllDir, 'sherpa-onnx-c-api.dll'));
}

Future<void> main(List<String> args) async {
  preloadNativeLibraries();
  if (args.length < 2) {
    stderr.writeln('usage: dart run tool/asr_spike.dart <model_dir> <wav> [lang]');
    exitCode = 2;
    return;
  }
  final recognizer = SherpaWhisperRecognizer(modelDir: args[0]);
  final result = await recognizer.transcribeFile(
    args[1],
    languageHint: args.length > 2 ? args[2] : '',
  );
  final rtf = result.audioDuration.inMilliseconds == 0
      ? 0
      : result.processingTime.inMilliseconds /
          result.audioDuration.inMilliseconds;
  stdout.writeln('model: ${result.modelId}');
  stdout.writeln('language: ${result.language}');
  stdout.writeln('audio: ${result.audioDuration.inMilliseconds} ms');
  stdout.writeln('processing: ${result.processingTime.inMilliseconds} ms');
  stdout.writeln('rtf: ${rtf.toStringAsFixed(2)}');
  stdout.writeln('text: ${result.text}');
}
