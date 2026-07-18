import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:potok/infrastructure/asr/sherpa_whisper_recognizer.dart';
import 'package:potok/infrastructure/audio_recorder.dart';

void main() {
  final modelDir = p.join(
    Directory.current.path,
    'assets',
    'models',
    'default',
  );
  final hasModel =
      !Platform.isWindows &&
      File(p.join(modelDir, 'tiny-encoder.int8.onnx')).existsSync();

  Future<String?> windowsNativeLibraryDir() async {
    if (!Platform.isWindows) return null;
    final config =
        json.decode(
              await File(
                p.join(
                  Directory.current.path,
                  '.dart_tool',
                  'package_config.json',
                ),
              ).readAsString(),
            )
            as Map<String, Object?>;
    final packages = config['packages']! as List<Object?>;
    final entry = packages.cast<Map<String, Object?>>().firstWhere(
      (item) => item['name'] == 'sherpa_onnx_windows',
    );
    final root = Uri.parse(entry['rootUri']! as String).toFilePath();
    return p.join(root, 'windows');
  }

  test(
    'packaged sherpa Whisper model loads and decodes local WAV',
    () async {
      final temp = await Directory.systemTemp.createTemp('potok_asr_smoke');
      try {
        final audio = File(p.join(temp.path, 'silence.wav'));
        await audio.writeAsBytes([
          ...buildPcm16WavHeader(dataBytes: 32000),
          ...List<int>.filled(32000, 0),
        ]);

        final recognizer = SherpaWhisperRecognizer(
          modelDir: modelDir,
          nativeLibraryDir: await windowsNativeLibraryDir(),
        );
        final result = await recognizer.transcribeFile(audio.path);

        expect(recognizer.engineId, 'sherpa-onnx');
        expect(result.audioDuration, const Duration(seconds: 1));
      } finally {
        await temp.delete(recursive: true);
      }
    },
    skip: hasModel
        ? false
        : Platform.isWindows
        ? 'flutter_tester preloads an incompatible ONNX Runtime; use tool/asr_model_smoke.dart'
        : 'bundled model assets were not prepared',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
