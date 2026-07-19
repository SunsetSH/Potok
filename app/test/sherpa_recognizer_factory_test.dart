import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:potok/infrastructure/asr/sherpa_recognizer_factory.dart';
import 'package:potok/infrastructure/asr/sherpa_transducer_recognizer.dart';
import 'package:potok/infrastructure/asr/sherpa_whisper_recognizer.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('potok_recognizer_factory');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<void> writeManifest(String modelType) => File(
    p.join(temp.path, 'potok-model.json'),
  ).writeAsString(json.encode({'model_type': modelType}));

  test('picks SherpaWhisperRecognizer for model_type "whisper"', () async {
    await writeManifest('whisper');
    expect(createSherpaRecognizer(temp.path), isA<SherpaWhisperRecognizer>());
  });

  test('picks SherpaTransducerRecognizer for model_type "nemo_transducer" '
      '(GigaAM/Parakeet)', () async {
    await writeManifest('nemo_transducer');
    expect(
      createSherpaRecognizer(temp.path),
      isA<SherpaTransducerRecognizer>(),
    );
  });

  test('defaults to whisper when the manifest is missing (dev fallback)', () {
    expect(createSherpaRecognizer(temp.path), isA<SherpaWhisperRecognizer>());
  });

  test('defaults to whisper when the manifest is corrupted', () async {
    await File(p.join(temp.path, 'potok-model.json')).writeAsString('{bad');
    expect(createSherpaRecognizer(temp.path), isA<SherpaWhisperRecognizer>());
  });
}
