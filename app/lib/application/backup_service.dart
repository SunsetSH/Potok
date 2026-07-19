import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../domain/clock.dart';
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
      checkCancelled();
      // Консистентный снапшот без WAL: VACUUM INTO новый файл.
      final snapshotFile = File(snapshotPath);
      if (snapshotFile.existsSync()) await snapshotFile.delete();
      await db.customStatement('VACUUM INTO ?', [snapshotPath]);

      // Ready-ассеты и counts читаются из самого снапшота: состав архива
      // всегда согласован с БД внутри него (включая корзину).
      final snapshot = _readSnapshot(snapshotPath);
      final assets = snapshot.assetPaths;

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

        for (final relativePath in assets) {
          checkCancelled();
          final file = File(media.absolutePath(relativePath));
          if (!file.existsSync()) {
            // Файл пропал вне протокола — честно пропускаем, репорт в итоге.
            missing++;
            step();
            continue;
          }
          final zipName = BackupFormat.mediaPrefix + _toPosix(relativePath);
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
            'notes': snapshot.notes,
            'projects': snapshot.projects,
            'tags': snapshot.tags,
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

      // Атомарная замена: старый бэкап уезжает в .bak и удаляется только
      // после успешного rename нового; сбой rename откатывает .bak обратно.
      final target = File(targetPath);
      final previousPath = '$targetPath.bak';
      final previous = File(previousPath);
      if (previous.existsSync()) await previous.delete();
      var movedPrevious = false;
      if (target.existsSync()) {
        await target.rename(previousPath);
        movedPrevious = true;
      }
      try {
        await File(zipTempPath).rename(targetPath);
      } catch (_) {
        if (movedPrevious) {
          try {
            await File(previousPath).rename(targetPath);
          } on FileSystemException {
            // Старый бэкап остаётся в .bak — данные не уничтожены.
          }
        }
        rethrow;
      }
      if (movedPrevious) {
        try {
          await File(previousPath).delete();
        } on FileSystemException {
          // Оставшийся .bak безвреден и перезапишется следующим бэкапом.
        }
      }
      return BackupResult(
        path: targetPath,
        sizeBytes: target.lengthSync(),
        noteCount: snapshot.notes,
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

  /// Read-only чтение снапшота: список ready-ассетов и counts согласованы
  /// с БД, которая попадёт в архив.
  static ({List<String> assetPaths, int notes, int projects, int tags})
  _readSnapshot(String snapshotPath) {
    final database = sqlite.sqlite3.open(
      snapshotPath,
      mode: sqlite.OpenMode.readOnly,
    );
    try {
      int count(String table) {
        final value = database
            .select('SELECT COUNT(*) AS c FROM $table')
            .first
            .values
            .first;
        return value is int ? value : 0;
      }

      final assetPaths = [
        for (final row in database.select(
          "SELECT relative_path FROM media_assets "
          "WHERE lifecycle_state = 'ready' ORDER BY relative_path",
        ))
          row.values.first as String,
      ];
      return (
        assetPaths: assetPaths,
        notes: count('notes'),
        projects: count('projects'),
        tags: count('tags'),
      );
    } finally {
      database.close();
    }
  }

  static String _toPosix(String relativePath) =>
      p.posix.joinAll(p.split(relativePath));

  static Future<String> _sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
