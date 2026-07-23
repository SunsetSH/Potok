import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:potok/infrastructure/asr/sherpa_asr_worker.dart';

void main() {
  test('long leading silence is trimmed with speech padding', () {
    const sampleRate = 1000;
    final samples = Float32List(42000);
    for (var index = 40000; index < samples.length; index++) {
      samples[index] = 0.2;
    }

    final trimmed = trimLongEdgeSilence(samples, sampleRate);

    expect(trimmed.length, 2400);
    expect(trimmed.first, 0);
    expect(trimmed[400], closeTo(0.2, 0.001));
  });

  test('short pauses and completely silent audio stay intact', () {
    const sampleRate = 1000;
    final shortPause = Float32List(2500);
    for (var index = 1000; index < 2000; index++) {
      shortPause[index] = 0.1;
    }
    final silence = Float32List(5000);

    expect(trimLongEdgeSilence(shortPause, sampleRate).length, 2500);
    expect(
      identical(trimLongEdgeSilence(silence, sampleRate), silence),
      isTrue,
    );
  });
}
