import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/clipboard_image_reader.dart';

void main() {
  test('detects encoded clipboard formats by magic bytes', () {
    expect(
      detectClipboardImageExtension(
        Uint8List.fromList(const [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]),
      ),
      'png',
    );
    expect(
      detectClipboardImageExtension(
        Uint8List.fromList(const [0xFF, 0xD8, 0xFF]),
      ),
      'jpg',
    );
    expect(
      detectClipboardImageExtension(
        Uint8List.fromList(const [
          0x52,
          0x49,
          0x46,
          0x46,
          0,
          0,
          0,
          0,
          0x57,
          0x45,
          0x42,
          0x50,
        ]),
      ),
      'webp',
    );
    expect(
      detectClipboardImageExtension(
        Uint8List.fromList(const [0x42, 0x4D, 0, 0]),
      ),
      'bmp',
    );
    expect(
      detectClipboardImageExtension(Uint8List.fromList(const [1, 2, 3])),
      isNull,
    );
  });
}
