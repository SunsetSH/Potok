import 'dart:io';
import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

import '../application/clipboard_image_reader.dart';

class SystemClipboardImageReader implements ClipboardImageReader {
  @override
  Future<ClipboardImage?> readImage() async {
    final bytes = await Pasteboard.image;
    if (bytes != null && bytes.isNotEmpty) return _validated(bytes);

    // Copying an image file in Explorer provides CF_HDROP rather than CF_DIB.
    // Android file entries are content URIs, already handled by image above.
    if (!Platform.isWindows) return null;
    for (final path in await Pasteboard.files()) {
      try {
        final file = File(path);
        final stat = file.statSync();
        if (stat.type != FileSystemEntityType.file) continue;
        if (stat.size > maxClipboardImageBytes) {
          throw const ClipboardImageReadException(
            'Изображение больше 10 МБ — используйте файл меньшего размера',
          );
        }
        if (stat.size <= 0) continue;
        final fileBytes = await file.readAsBytes();
        final extension = detectClipboardImageExtension(fileBytes);
        if (extension != null) {
          return ClipboardImage(bytes: fileBytes, extension: extension);
        }
      } on ClipboardImageReadException {
        rethrow;
      } on FileSystemException {
        // Clipboard file lists can become stale between copy and paste.
        continue;
      }
    }
    return null;
  }

  ClipboardImage _validated(Uint8List bytes) {
    if (bytes.length > maxClipboardImageBytes) {
      throw const ClipboardImageReadException(
        'Изображение больше 10 МБ — используйте файл меньшего размера',
      );
    }
    final extension = detectClipboardImageExtension(bytes);
    if (extension == null) {
      throw const ClipboardImageReadException(
        'Содержимое буфера не является поддерживаемым изображением',
      );
    }
    return ClipboardImage(bytes: bytes, extension: extension);
  }
}
