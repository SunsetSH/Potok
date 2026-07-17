import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../domain/clock.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/media_store.dart';

/// Формат контейнера `*.potok-backup` (ADR-006, ТЗ 0.9).
abstract final class BackupFormat {
  static const format = 'potok.backup';
  static const formatVersion = 1;
  static const manifestName = 'manifest.json';
  static const databaseName = 'database.sqlite';
  static const mediaPrefix = 'media/';
  static const fileExtension = 'potok-backup';
}

class BackupCancelled implements Exception {
  const BackupCancelled();
}

/// Ожидаемая ошибка backup: короткое сообщение без пользовательских данных.
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => 'BackupException: $message';
}

class BackupResult {
  final String path;
  final int sizeBytes;
  final int noteCount;
  final int assetCount;

  /// Ready-ассеты, чьи файлы отсутствовали на диске и не попали в копию.
  final int missingAssetCount;

  const BackupResult({
    required this.path,
    required this.sizeBytes,
    required this.noteCount,
    required this.assetCount,
    required this.missingAssetCount,
  });
}

/// Создание резервной копии: VACUUM INTO снапшот -> стриминг ZIP во временный
/// файл рядом с целевым -> sha256 всех вложений -> manifest последним ->
/// atomic rename. Ошибка на любом шаге не оставляет частичных файлов.
class BackupService {
  final AppDatabase db;
  final MediaStore media;
  final Clock clock;

  BackupService({required this.db, required this.media, required this.clock});

  Future<BackupResult> createBackup({
    required String targetPath,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final now = clock.nowUtcMillis();
    final targetDir = p.dirname(targetPath);
    await Directory(targetDir).create(recursive: true);
    final snapshotPath = '$targetPath.db-$now.tmp';
    final zipTempPath = '$targetPath.$now.tmp';

    void checkCancelled() {
      if (isCancelled?.call() ?? false) throw const BackupCancelled();
    }

    try {
      // Ready-ассеты (включая корзину: полная копия восстанавливает и её).
      final assets =
          await (db.select(db.mediaAssets)..where(
                (a) => a.lifecycleState.equalsValue(AssetLifecycle.ready),
              ))
              .get();
      final counts = await _counts();

      checkCancelled();
      // Консистентный снапшот без WAL: VACUUM INTO новый файл.
      final snapshotFile = File(snapshotPath);
      if (snapshotFile.existsSync()) await snapshotFile.delete();
      await db.customStatement('VACUUM INTO ?', [snapshotPath]);

      final total = assets.length + 2; // db + media + manifest
      var done = 0;
      void step() => onProgress?.call(++done, total);

      final hashes = <String, String>{};
      final encoder = ZipFileEncoder();
      encoder.create(zipTempPath);
      var encoderOpen = true;
      var missing = 0;
      var includedAssets = 0;
      try {
        checkCancelled();
        hashes[BackupFormat.databaseName] = await _sha256Of(snapshotFile);
        await encoder.addFile(snapshotFile, BackupFormat.databaseName);
        step();

        for (final asset in assets) {
          checkCancelled();
          final file = File(media.absolutePath(asset.relativePath));
          if (!file.existsSync()) {
            // Файл пропал вне протокола — честно пропускаем, репорт в итоге.
            missing++;
            step();
            continue;
          }
          final zipName =
              BackupFormat.mediaPrefix + _toPosix(asset.relativePath);
          hashes[zipName] = await _sha256Of(file);
          await encoder.addFile(file, zipName);
          includedAssets++;
          step();
        }

        checkCancelled();
        final manifest = <String, Object?>{
          'format': BackupFormat.format,
          'format_version': BackupFormat.formatVersion,
          'created_at_utc': now,
          'schema_version': db.schemaVersion,
          'counts': {
            'notes': counts.notes,
            'projects': counts.projects,
            'tags': counts.tags,
            'assets': includedAssets,
          },
          'files': hashes,
        };
        encoder.addArchiveFile(
          ArchiveFile.string(BackupFormat.manifestName, jsonEncode(manifest)),
        );
        await encoder.close();
        encoderOpen = false;
        step();
      } finally {
        if (encoderOpen) await encoder.close();
      }

      final target = File(targetPath);
      if (target.existsSync()) await target.delete();
      await File(zipTempPath).rename(targetPath);
      return BackupResult(
        path: targetPath,
        sizeBytes: target.lengthSync(),
        noteCount: counts.notes,
        assetCount: includedAssets,
        missingAssetCount: missing,
      );
    } finally {
      for (final path in [snapshotPath, zipTempPath]) {
        final file = File(path);
        if (file.existsSync()) {
          try {
            await file.delete();
          } on FileSystemException {
            // Temp-мусор не должен маскировать исходную ошибку.
          }
        }
      }
    }
  }

  Future<({int notes, int projects, int tags})> _counts() async {
    Future<int> count(TableInfo<Table, Object?> table) async {
      final result = await (db.selectOnly(
        table,
      )..addColumns([countAll()])).getSingle();
      return result.read(countAll()) ?? 0;
    }

    return (
      notes: await count(db.notes),
      projects: await count(db.projects),
      tags: await count(db.tags),
    );
  }

  static String _toPosix(String relativePath) =>
      p.posix.joinAll(p.split(relativePath));

  static Future<String> _sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
