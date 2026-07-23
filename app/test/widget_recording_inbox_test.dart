import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:potok/infrastructure/widget_recording_inbox.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('potok_widget_inbox_test');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('accepts a bounded atomic WAV and acknowledges both files', () async {
    const id = '019c0000-0000-7000-8000-000000000001';
    final audio = File('${temp.path}${Platform.pathSeparator}$id.wav');
    await audio.writeAsBytes([
      ...ascii.encode('RIFF'),
      36,
      0,
      0,
      0,
      ...ascii.encode('WAVE'),
      ...List<int>.filled(64, 0),
    ]);
    final metadata = File('${temp.path}${Platform.pathSeparator}$id.json');
    await metadata.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'id': id,
        'file': '$id.wav',
        'durationMs': 1000,
        'sampleRateHz': 16000,
        'channels': 1,
      }),
    );

    final inbox = WidgetRecordingInbox(temp);
    final entries = await inbox.pending();
    expect(entries, hasLength(1));
    expect(entries.single.id, id);

    await inbox.acknowledge(entries.single);
    expect(await audio.exists(), isFalse);
    expect(await metadata.exists(), isFalse);
  });

  test('quarantines metadata that attempts a path substitution', () async {
    const id = '019c0000-0000-7000-8000-000000000002';
    final metadata = File('${temp.path}${Platform.pathSeparator}$id.json');
    await metadata.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'id': id,
        'file': '../outside.wav',
        'durationMs': 1000,
        'sampleRateHz': 16000,
        'channels': 1,
      }),
    );

    expect(await WidgetRecordingInbox(temp).pending(), isEmpty);
    expect(await File('${metadata.path}.invalid').exists(), isTrue);
  });
}
