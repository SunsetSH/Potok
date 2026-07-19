import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../domain/clock.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/media_store.dart';
import 'notes_service.dart';

/// Reconciles the DB lifecycle with managed files after an unclean shutdown.
/// It never guesses from a user-visible filename: only DB-owned relative paths
/// inside [MediaStore.root] are touched.
class MediaRepairService {
  final AppDatabase db;
  final MediaStore media;
  final NotesService notes;
  final Clock clock;

  const MediaRepairService({
    required this.db,
    required this.media,
    required this.notes,
    required this.clock,
  });

  Future<MediaRepairReport> reconcile({
    Duration stagingGrace = const Duration(minutes: 10),
  }) async {
    final assets = await db.select(db.mediaAssets).get();
    final cutoff = clock.nowUtcMillis() - stagingGrace.inMilliseconds;
    var recoveredAudio = 0;
    var recoveredImages = 0;
    var markedMissing = 0;
    var restored = 0;
    var discarded = 0;

    for (final asset in assets) {
      switch (asset.lifecycleState) {
        case AssetLifecycle.deleted:
          await media.discard(asset.relativePath);
          discarded++;
          continue;
        case AssetLifecycle.staging:
          final recovered = await _recoverStaging(asset);
          if (recovered) {
            if (asset.kind == AssetKind.audio) {
              recoveredAudio++;
            } else {
              recoveredImages++;
            }
          } else if (asset.updatedAtUtc <= cutoff) {
            await _discardStaging(asset);
            discarded++;
          }
          continue;
        case AssetLifecycle.ready:
          if (!await _matchesPublishedFile(asset)) {
            markedMissing += await _setLifecycle(
              asset,
              from: AssetLifecycle.ready,
              to: AssetLifecycle.missing,
            );
          }
          continue;
        case AssetLifecycle.missing:
          if (await _matchesPublishedFile(asset)) {
            restored += await _setLifecycle(
              asset,
              from: AssetLifecycle.missing,
              to: AssetLifecycle.ready,
            );
          }
          continue;
      }
    }

    final orphanPartialsRemoved = await _pruneOrphanPartials(
      assets,
      cutoffMillis: cutoff,
    );
    return MediaRepairReport(
      recoveredAudio: recoveredAudio,
      recoveredImages: recoveredImages,
      markedMissing: markedMissing,
      restored: restored,
      discarded: discarded,
      orphanPartialsRemoved: orphanPartialsRemoved,
    );
  }

  Future<bool> _recoverStaging(MediaAsset asset) async {
    try {
      if (asset.kind == AssetKind.audio) {
        final finalFile = File(media.absolutePath(asset.relativePath));
        final partial = File(media.stagingPath(asset.relativePath));
        if (!finalFile.existsSync() && !partial.existsSync()) return false;
        await notes.recoverStagedAudio(asset);
        return true;
      }

      // Image import validates before copying. Only a final name proves the
      // atomic rename completed; a partial may still be truncated.
      final result = await media.inspect(asset.relativePath);
      if (result == null) return false;
      final updated =
          await (db.update(db.mediaAssets)..where(
                (row) =>
                    row.id.equals(asset.id) &
                    row.lifecycleState.equalsValue(AssetLifecycle.staging),
              ))
              .write(
                MediaAssetsCompanion(
                  lifecycleState: const Value(AssetLifecycle.ready),
                  sizeBytes: Value(result.sizeBytes),
                  sha256: Value(result.sha256hex),
                  updatedAtUtc: Value(clock.nowUtcMillis()),
                ),
              );
      return updated == 1;
    } on MediaFinalizeException {
      return false;
    } on StateError {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  Future<bool> _matchesPublishedFile(MediaAsset asset) async {
    try {
      final result = await media.inspect(
        asset.relativePath,
        validateAudio: asset.kind == AssetKind.audio,
      );
      if (result == null) return false;
      final expected = asset.sha256;
      return expected == null || expected == result.sha256hex;
    } on MediaFinalizeException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  Future<int> _setLifecycle(
    MediaAsset asset, {
    required AssetLifecycle from,
    required AssetLifecycle to,
  }) {
    return (db.update(db.mediaAssets)..where(
          (row) =>
              row.id.equals(asset.id) & row.lifecycleState.equalsValue(from),
        ))
        .write(
          MediaAssetsCompanion(
            lifecycleState: Value(to),
            updatedAtUtc: Value(clock.nowUtcMillis()),
          ),
        );
  }

  Future<void> _discardStaging(MediaAsset asset) async {
    if (asset.kind == AssetKind.audio) {
      final note = await (db.select(
        db.notes,
      )..where((row) => row.id.equals(asset.ownerNoteId))).getSingle();
      await notes.abortAudioNote(
        StagedRecording(
          noteId: asset.ownerNoteId,
          assetId: asset.id,
          relativePath: asset.relativePath,
          stagingPath: media.stagingPath(asset.relativePath),
          createsNote: note.deletedAtUtc != null,
          baseRevision: note.deletedAtUtc == null ? note.revision : null,
        ),
      );
      return;
    }
    await media.discard(asset.relativePath);
    await (db.delete(
      db.mediaAssets,
    )..where((row) => row.id.equals(asset.id))).go();
  }

  Future<int> _pruneOrphanPartials(
    List<MediaAsset> assets, {
    required int cutoffMillis,
  }) async {
    if (!media.root.existsSync()) return 0;
    final known = assets
        .map((asset) => p.normalize(media.stagingPath(asset.relativePath)))
        .toSet();
    var removed = 0;
    await for (final entity in media.root.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.partial')) continue;
      if (known.contains(p.normalize(entity.path))) continue;
      try {
        final modified = entity.lastModifiedSync();
        if (modified.toUtc().millisecondsSinceEpoch > cutoffMillis) continue;
        await entity.delete();
        removed++;
      } on FileSystemException {
        // Файл исчез или занят — пропускаем, приберём в следующий запуск.
      }
    }
    return removed;
  }
}

class MediaRepairReport {
  final int recoveredAudio;
  final int recoveredImages;
  final int markedMissing;
  final int restored;
  final int discarded;
  final int orphanPartialsRemoved;

  const MediaRepairReport({
    required this.recoveredAudio,
    required this.recoveredImages,
    required this.markedMissing,
    required this.restored,
    required this.discarded,
    required this.orphanPartialsRemoved,
  });
}
