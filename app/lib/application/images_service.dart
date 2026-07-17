import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../domain/clock.dart';
import '../domain/document.dart';
import '../domain/id_generator.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/media_store.dart';

/// Ожидаемые отказы прикрепления изображения — показываются пользователю.
class ImageAttachException implements Exception {
  final String message;
  const ImageAttachException(this.message);

  @override
  String toString() => 'ImageAttachException: $message';
}

typedef ImageReconcileReport = ({
  int markedDeleted,
  int filesRemoved,
  int cleanupFailures,
  int corruptDocuments,
});

/// Inline-изображения документа (FR-DOC-003): managed file через протокол
/// MediaStore (staging copy → validate → sha256 → atomic rename → ready).
class ImagesService {
  final AppDatabase db;
  final MediaStore media;
  final Clock clock;
  final IdGenerator ids;

  ImagesService({
    required this.db,
    required this.media,
    required this.clock,
    required this.ids,
  });

  static const maxImageBytes = 10 * 1024 * 1024; // 10 МБ (ТЗ FR-DOC-003)

  static const _mimeByExtension = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  /// Копирует [sourcePath] в media-хранилище и возвращает `ready`-asset,
  /// привязанный к заметке. Валидация источника — до любых следов в staging;
  /// при сбое после — компенсация (staging-файл и строка удаляются).
  ///
  /// TODO(WP-05): даунскейл больших изображений до 2048px по длинной стороне
  /// (требует image-зависимости, в WP-04 не разрешена).
  Future<MediaAsset> attachImage(Note note, String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const ImageAttachException('Файл изображения не найден');
    }
    final sourceLength = source.lengthSync();
    if (sourceLength <= 0) {
      throw const ImageAttachException('Файл изображения пуст');
    }
    if (sourceLength > maxImageBytes) {
      throw const ImageAttachException(
        'Изображение больше 10 МБ — выберите файл меньшего размера',
      );
    }
    final extension = p
        .extension(sourcePath)
        .replaceFirst('.', '')
        .toLowerCase();
    final mime = _mimeByExtension[extension];
    if (mime == null) {
      throw const ImageAttachException('Поддерживаются только JPG, PNG и WebP');
    }
    if (!_hasExpectedSignature(source, extension)) {
      throw const ImageAttachException(
        'Содержимое файла не соответствует формату изображения',
      );
    }

    final assetId = ids.newId();
    final relativePath = media.relativePathFor(assetId, extension);
    final now = clock.nowUtcMillis();
    // Строка в `staging` до появления байтов: незавершённый asset никогда
    // не выглядит готовым.
    await db
        .into(db.mediaAssets)
        .insert(
          MediaAssetsCompanion.insert(
            id: assetId,
            ownerNoteId: note.id,
            kind: AssetKind.image,
            relativePath: relativePath,
            mimeType: mime,
            lifecycleState: AssetLifecycle.staging,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
    try {
      await media.prepareStaging(relativePath);
      await source.copy(media.stagingPath(relativePath));
      final result = await media.finalize(relativePath);
      final readyAt = clock.nowUtcMillis();
      await (db.update(
        db.mediaAssets,
      )..where((a) => a.id.equals(assetId))).write(
        MediaAssetsCompanion(
          lifecycleState: const Value(AssetLifecycle.ready),
          sizeBytes: Value(result.sizeBytes),
          sha256: Value(result.sha256hex),
          updatedAtUtc: Value(readyAt),
        ),
      );
    } catch (e) {
      // Компенсация: следов неудачной попытки не остаётся.
      await media.discardStaging(relativePath);
      await (db.delete(
        db.mediaAssets,
      )..where((a) => a.id.equals(assetId))).go();
      rethrow;
    }
    return (db.select(
      db.mediaAssets,
    )..where((a) => a.id.equals(assetId))).getSingle();
  }

  /// Резолв embed `asset://<id>` → файл на диске. `null` — asset не готов
  /// или файл отсутствует (UI показывает плейсхолдер «Изображение
  /// недоступно»).
  Future<File?> resolveReadyImageFile(String assetId) async {
    final asset = await (db.select(
      db.mediaAssets,
    )..where((a) => a.id.equals(assetId))).getSingleOrNull();
    if (asset == null ||
        asset.kind != AssetKind.image ||
        asset.lifecycleState != AssetLifecycle.ready ||
        asset.deletedAtUtc != null) {
      return null;
    }
    final file = File(media.absolutePath(asset.relativePath));
    return file.existsSync() ? file : null;
  }

  /// Marks old, unreferenced images as tombstones and removes their bytes.
  /// A malformed document aborts marking entirely: deleting too little is
  /// preferable to losing a user's only media copy.
  Future<ImageReconcileReport> reconcileOrphanImages({
    required Duration gracePeriod,
  }) async {
    if (gracePeriod.isNegative) {
      throw ArgumentError.value(gracePeriod, 'gracePeriod', 'must be >= 0');
    }
    final referenced = <String>{};
    var corruptDocuments = 0;
    String? lastNoteId;
    while (true) {
      final query = db.select(db.notes)
        ..orderBy([(note) => OrderingTerm.asc(note.id)])
        ..limit(500);
      if (lastNoteId != null) {
        query.where((note) => note.id.isBiggerThanValue(lastNoteId!));
      }
      final page = await query.get();
      if (page.isEmpty) break;
      for (final note in page) {
        try {
          referenced.addAll(
            PotokDocument.decode(note.documentJson).managedAssetIds,
          );
        } on FormatException {
          corruptDocuments++;
        }
      }
      lastNoteId = page.last.id;
      await Future<void>.delayed(Duration.zero);
    }

    var markedDeleted = 0;
    final now = clock.nowUtcMillis();
    if (corruptDocuments == 0) {
      final cutoff = now - gracePeriod.inMilliseconds;
      final readyImages =
          await (db.select(db.mediaAssets)..where(
                (asset) =>
                    asset.kind.equalsValue(AssetKind.image) &
                    asset.lifecycleState.equalsValue(AssetLifecycle.ready) &
                    asset.deletedAtUtc.isNull() &
                    asset.createdAtUtc.isSmallerOrEqualValue(cutoff),
              ))
              .get();
      await db.transaction(() async {
        for (final asset in readyImages) {
          if (referenced.contains(asset.id)) continue;
          markedDeleted +=
              await (db.update(db.mediaAssets)..where(
                    (row) =>
                        row.id.equals(asset.id) &
                        row.lifecycleState.equalsValue(AssetLifecycle.ready) &
                        row.deletedAtUtc.isNull(),
                  ))
                  .write(
                    MediaAssetsCompanion(
                      lifecycleState: const Value(AssetLifecycle.deleted),
                      deletedAtUtc: Value(now),
                      updatedAtUtc: Value(now),
                    ),
                  );
        }
      });
    }

    var filesRemoved = 0;
    var cleanupFailures = 0;
    final tombstones =
        await (db.select(db.mediaAssets)..where(
              (asset) =>
                  asset.kind.equalsValue(AssetKind.image) &
                  asset.lifecycleState.equalsValue(AssetLifecycle.deleted),
            ))
            .get();
    for (final asset in tombstones) {
      try {
        final hadBytes =
            File(media.absolutePath(asset.relativePath)).existsSync() ||
            File(media.stagingPath(asset.relativePath)).existsSync();
        await media.discard(asset.relativePath);
        if (hadBytes) filesRemoved++;
      } on FileSystemException {
        cleanupFailures++;
      }
    }
    return (
      markedDeleted: markedDeleted,
      filesRemoved: filesRemoved,
      cleanupFailures: cleanupFailures,
      corruptDocuments: corruptDocuments,
    );
  }

  static bool _hasExpectedSignature(File source, String extension) {
    final handle = source.openSync();
    try {
      final header = handle.readSync(12);
      return switch (extension) {
        'jpg' || 'jpeg' =>
          header.length >= 3 &&
              header[0] == 0xFF &&
              header[1] == 0xD8 &&
              header[2] == 0xFF,
        'png' =>
          header.length >= 8 &&
              _matches(header, 0, const [
                0x89,
                0x50,
                0x4E,
                0x47,
                0x0D,
                0x0A,
                0x1A,
                0x0A,
              ]),
        'webp' =>
          header.length >= 12 &&
              _matches(header, 0, const [0x52, 0x49, 0x46, 0x46]) &&
              _matches(header, 8, const [0x57, 0x45, 0x42, 0x50]),
        _ => false,
      };
    } finally {
      handle.closeSync();
    }
  }

  static bool _matches(List<int> bytes, int offset, List<int> signature) {
    for (var index = 0; index < signature.length; index++) {
      if (bytes[offset + index] != signature[index]) return false;
    }
    return true;
  }
}
