import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:potok/infrastructure/audio_recorder.dart';

void main() {
  test('PCM stream is wrapped in a valid mono 16 kHz WAV header', () {
    final header = buildPcm16WavHeader(dataBytes: 32000);
    final data = ByteData.sublistView(header);

    expect(ascii.decode(header.sublist(0, 4)), 'RIFF');
    expect(data.getUint32(4, Endian.little), 32036);
    expect(ascii.decode(header.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(20, Endian.little), 1);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint16(34, Endian.little), 16);
    expect(ascii.decode(header.sublist(36, 40)), 'data');
    expect(data.getUint32(40, Endian.little), 32000);
  });

  test('PCM RMS level reacts to silence and signal', () {
    final silence = Uint8List(16);
    final signal = ByteData(16);
    for (var offset = 0; offset < signal.lengthInBytes; offset += 2) {
      signal.setInt16(offset, offset.isEven ? 12000 : -12000, Endian.little);
    }

    expect(pcm16RmsLevel(silence), 0);
    expect(pcm16RmsLevel(signal.buffer.asUint8List()), greaterThan(0.7));
  });
}
