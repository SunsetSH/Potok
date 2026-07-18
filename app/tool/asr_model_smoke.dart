import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:potok/infrastructure/asr/sherpa_whisper_recognizer.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/asr_model_smoke.dart <model-dir> [native-library-dir]',
    );
    exitCode = 64;
    return;
  }
  final modelDir = Directory(arguments.first).absolute.path;
  final nativeLibraryDir = arguments.length == 2
      ? Directory(arguments[1]).absolute.path
      : null;
  final temp = await Directory.systemTemp.createTemp('potok_asr_smoke');
  try {
    final audio = File(p.join(temp.path, 'silence.wav'));
    final pcm = ByteData(32000);
    for (var index = 0; index < 16000; index++) {
      final sample = (math.sin(2 * math.pi * 440 * index / 16000) * 4096)
          .round();
      pcm.setInt16(index * 2, sample, Endian.little);
    }
    await audio.writeAsBytes([
      ..._wavHeader(32000),
      ...pcm.buffer.asUint8List(),
    ]);
    final recognizer = SherpaWhisperRecognizer(
      modelDir: modelDir,
      nativeLibraryDir: nativeLibraryDir,
    );
    final result = await recognizer.transcribeFile(audio.path);
    stdout.writeln(
      'ASR smoke OK: engine=${recognizer.engineId}, model=${recognizer.modelId}, '
      'audio_ms=${result.audioDuration.inMilliseconds}, output_chars=${result.text.length}',
    );
  } finally {
    await temp.delete(recursive: true);
  }
}

Uint8List _wavHeader(int dataBytes) {
  final data = ByteData(44);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataBytes, Endian.little);
  return data.buffer.asUint8List();
}
