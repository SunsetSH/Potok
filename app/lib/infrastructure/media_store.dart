import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// File side of the media finalize protocol (ADR-004):
/// DB `staging` -> write `<id>.<ext>.partial` (same volume) -> flush/close ->
/// validate -> SHA-256 -> atomic rename -> DB `ready`.
class MediaStore {
  final Directory root;

  MediaStore(this.root);

  /// Shard by the first two id chars to keep directories small.
  String relativePathFor(String assetId, String extension) {
    if (!RegExp(r'^[A-Za-z0-9_-]{3,128}$').hasMatch(assetId)) {
      throw ArgumentError.value(assetId, 'assetId', 'unsafe media id');
    }
    if (!RegExp(r'^[A-Za-z0-9]{1,10}$').hasMatch(extension)) {
      throw ArgumentError.value(extension, 'extension', 'unsafe extension');
    }
    return p.join(assetId.substring(0, 2), '$assetId.$extension');
  }

  String absolutePath(String relativePath) {
    if (relativePath.isEmpty || p.isAbsolute(relativePath)) {
      throw ArgumentError.value(relativePath, 'relativePath', 'unsafe path');
    }
    final rootPath = p.normalize(p.absolute(root.path));
    final result = p.normalize(p.join(rootPath, relativePath));
    if (!p.isWithin(rootPath, result)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'path escapes root',
      );
    }
    return result;
  }

  /// Path the recorder writes to. Lives next to the final file (same volume)
  /// so the final step is an atomic rename.
  String stagingPath(String relativePath) =>
      '${absolutePath(relativePath)}.partial';

  Future<void> prepareStaging(String relativePath) async {
    await Directory(
      p.dirname(absolutePath(relativePath)),
    ).create(recursive: true);
  }

  /// Validates and promotes a staged file. Returns (sizeBytes, sha256hex).
  /// Throws [MediaFinalizeException] if the staged file is missing or empty.
  Future<({int sizeBytes, String sha256hex})> finalize(String relativePath) =>
      _finalize(relativePath, validateAudio: false);

  /// Audio promotion additionally verifies the container signature. This does
  /// not decode the stream, but rejects truncated/wrong-format output before a
  /// note can become visible.
  Future<({int sizeBytes, String sha256hex})> finalizeAudio(
    String relativePath,
  ) => _finalize(relativePath, validateAudio: true);

  Future<({int sizeBytes, String sha256hex})> _finalize(
    String relativePath, {
    required bool validateAudio,
  }) async {
    final partial = File(stagingPath(relativePath));
    if (!partial.existsSync()) {
      throw const MediaFinalizeException('staged file missing');
    }
    final size = partial.lengthSync();
    if (size <= 0) {
      throw const MediaFinalizeException('staged file is empty');
    }
    if (validateAudio &&
        !await _hasExpectedAudioSignature(
          partial,
          extension: p.extension(relativePath),
        )) {
      throw const MediaFinalizeException('invalid audio container');
    }
    final digest = await sha256.bind(partial.openRead()).first;
    final target = File(absolutePath(relativePath));
    await partial.rename(target.path);
    return (sizeBytes: size, sha256hex: digest.toString());
  }

  /// Checks a published file and returns its current integrity metadata.
  /// Missing files return null; invalid/truncated files throw.
  Future<({int sizeBytes, String sha256hex})?> inspect(
    String relativePath, {
    bool validateAudio = false,
  }) async {
    final file = File(absolutePath(relativePath));
    if (!file.existsSync()) return null;
    final size = file.lengthSync();
    if (size <= 0) {
      throw const MediaFinalizeException('published file is empty');
    }
    if (validateAudio &&
        !await _hasExpectedAudioSignature(
          file,
          extension: p.extension(relativePath),
        )) {
      throw const MediaFinalizeException('invalid audio container');
    }
    final digest = await sha256.bind(file.openRead()).first;
    return (sizeBytes: size, sha256hex: digest.toString());
  }

  Future<bool> _hasExpectedAudioSignature(
    File file, {
    required String extension,
  }) async {
    extension = extension.toLowerCase();
    final handle = await file.open();
    try {
      final header = await handle.read(12);
      if (header.length < 12) return false;
      if (extension == '.m4a') {
        return header[4] == 0x66 &&
            header[5] == 0x74 &&
            header[6] == 0x79 &&
            header[7] == 0x70;
      }
      if (extension == '.wav') {
        final riffWave =
            header[0] == 0x52 &&
            header[1] == 0x49 &&
            header[2] == 0x46 &&
            header[3] == 0x46 &&
            header[8] == 0x57 &&
            header[9] == 0x41 &&
            header[10] == 0x56 &&
            header[11] == 0x45;
        if (!riffWave) return false;
        // Наши записи — канонический 44-байтовый заголовок с 'data' на 36-м
        // байте: сверяем заявленный data-size с фактическим размером, чтобы
        // WAV c «обещанными», но не записанными байтами не стал ready.
        final rest = await handle.read(32);
        if (rest.length < 32) return false;
        final isDataChunk =
            rest[24] == 0x64 && // 'd'
            rest[25] == 0x61 && // 'a'
            rest[26] == 0x74 && // 't'
            rest[27] == 0x61; // 'a'
        if (!isDataChunk) return true; // нестандартный layout — не проверяем
        final dataSize =
            rest[28] | (rest[29] << 8) | (rest[30] << 16) | (rest[31] << 24);
        return await file.length() >= 44 + dataSize;
      }
      return false;
    } finally {
      await handle.close();
    }
  }

  /// Idempotent cleanup for failed/cancelled recordings.
  Future<void> discardStaging(String relativePath) async {
    final partial = File(stagingPath(relativePath));
    if (partial.existsSync()) await partial.delete();
  }

  /// Idempotent cleanup after the DB row has entered `deleted` lifecycle.
  /// Both names are checked because recovery may run at any crash point.
  Future<void> discard(String relativePath) async {
    await discardStaging(relativePath);
    final finalFile = File(absolutePath(relativePath));
    if (finalFile.existsSync()) await finalFile.delete();
  }
}

class MediaFinalizeException implements Exception {
  final String message;
  const MediaFinalizeException(this.message);

  @override
  String toString() => 'MediaFinalizeException: $message';
}
