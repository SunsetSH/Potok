import 'dart:typed_data';

const maxClipboardImageBytes = 10 * 1024 * 1024;

class ClipboardImageReadException implements Exception {
  final String message;

  const ClipboardImageReadException(this.message);

  @override
  String toString() => 'ClipboardImageReadException: $message';
}

class ClipboardImage {
  final Uint8List bytes;
  final String extension;

  const ClipboardImage({required this.bytes, required this.extension});
}

abstract interface class ClipboardImageReader {
  /// Читается только по явному paste action. `null` означает, что в буфере нет
  /// поддерживаемого изображения или platform clipboard недоступен.
  Future<ClipboardImage?> readImage();
}

/// Detects the encoded image format without trusting a platform MIME or file
/// extension. Windows clipboard DIB is returned by `pasteboard` as BMP bytes.
String? detectClipboardImageExtension(List<int> bytes) {
  bool matches(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (matches(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'png';
  }
  if (matches(0, const [0xFF, 0xD8, 0xFF])) return 'jpg';
  if (matches(0, const [0x52, 0x49, 0x46, 0x46]) &&
      matches(8, const [0x57, 0x45, 0x42, 0x50])) {
    return 'webp';
  }
  if (matches(0, const [0x42, 0x4D])) return 'bmp';
  return null;
}
