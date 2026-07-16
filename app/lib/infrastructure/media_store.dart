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
  String relativePathFor(String assetId, String extension) =>
      p.join(assetId.substring(0, 2), '$assetId.$extension');

  String absolutePath(String relativePath) => p.join(root.path, relativePath);

  /// Path the recorder writes to. Lives next to the final file (same volume)
  /// so the final step is an atomic rename.
  String stagingPath(String relativePath) =>
      '${absolutePath(relativePath)}.partial';

  Future<void> prepareStaging(String relativePath) async {
    await Directory(p.dirname(absolutePath(relativePath))).create(recursive: true);
  }

  /// Validates and promotes a staged file. Returns (sizeBytes, sha256hex).
  /// Throws [MediaFinalizeException] if the staged file is missing or empty.
  Future<({int sizeBytes, String sha256hex})> finalize(String relativePath) async {
    final partial = File(stagingPath(relativePath));
    if (!await partial.exists()) {
      throw const MediaFinalizeException('staged file missing');
    }
    final size = await partial.length();
    if (size <= 0) {
      throw const MediaFinalizeException('staged file is empty');
    }
    final digest = await sha256.bind(partial.openRead()).first;
    final target = File(absolutePath(relativePath));
    await partial.rename(target.path);
    return (sizeBytes: size, sha256hex: digest.toString());
  }

  /// Idempotent cleanup for failed/cancelled recordings.
  Future<void> discardStaging(String relativePath) async {
    final partial = File(stagingPath(relativePath));
    if (await partial.exists()) await partial.delete();
  }
}

class MediaFinalizeException implements Exception {
  final String message;
  const MediaFinalizeException(this.message);

  @override
  String toString() => 'MediaFinalizeException: $message';
}
