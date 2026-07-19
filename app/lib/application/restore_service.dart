import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'backup_service.dart';

/// Ожидаемая ошибка восстановления. Сообщение короткое, без содержимого
/// заметок и пользовательских путей — его можно показывать и логировать.
class RestoreException implements Exception {
  final String message;
  const RestoreException(this.message);

  @override
  String toString() => 'RestoreException: $message';
}

class RestoreCancelled implements Exception {
  const RestoreCancelled();
}

/// Проверенный кандидат в quarantine-каталоге. Рабочие данные ещё не тронуты.
class RestoreCandidate {
  final Directory quarantineDir;
  final File databaseFile;
  final Directory? mediaDir;
  final int noteCount;
  final int assetCount;

  const RestoreCandidate({
    required this.quarantineDir,
    required this.databaseFile,
    required this.mediaDir,
    required this.noteCount,
    required this.assetCount,
  });
}

/// Restore по ADR-006: распаковка в quarantine `<support>/restore/<gen>/`
/// с лимитами path/size/ratio, сверка sha256 c manifest, read-only проверка
/// SQLite (quick_check, foreign_key_check, schema_version), затем страховочная
/// копия текущих данных и перенос кандидата на место. Любая ошибка до
/// переключения не трогает рабочие данные; ошибка после — откат из копии.
class RestoreService {
  /// Лимит суммарного распакованного размера (zip bomb, ТЗ 0.10.2).
  static const maxTotalUncompressedBytes = 10 * 1024 * 1024 * 1024; // 10 ГБ

  /// Подозрительная степень сжатия допустима только для маленьких архивов.
  static const maxCompressionRatio = 200;
  static const ratioCheckFloorBytes = 64 * 1024 * 1024;

  final Directory supportDir;
  final String databaseFileName;
  final int currentSchemaVersion;

  RestoreService({
    required this.supportDir,
    required this.currentSchemaVersion,
    this.databaseFileName = 'potok.sqlite',
  });

  static int _generationSeq = 0;

  Directory get _restoreRoot => Directory(p.join(supportDir.path, 'restore'));

  /// Шаг 1: распаковка и полная проверка кандидата. Не трогает рабочие данные.
  Future<RestoreCandidate> prepare(
    String archivePath, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    // Millis + счётчик: поколения уникальны даже при быстрых повторах.
    final generation =
        '${DateTime.now().toUtc().millisecondsSinceEpoch}-${_generationSeq++}';
    final quarantine = Directory(p.join(_restoreRoot.path, generation));
    try {
      return await _prepareInto(
        quarantine,
        archivePath,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } catch (_) {
      await _deleteQuietly(quarantine);
      rethrow;
    }
  }

  Future<RestoreCandidate> _prepareInto(
    Directory quarantine,
    String archivePath, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() ?? false) throw const RestoreCancelled();
    }

    final archiveFile = File(archivePath);
    if (!archiveFile.existsSync()) {
      throw const RestoreException('файл копии не найден');
    }
    final archiveSize = archiveFile.lengthSync();

    final input = InputFileStream(archivePath);
    Archive archive;
    try {
      try {
        archive = ZipDecoder().decodeStream(input);
      } on Object {
        throw const RestoreException('архив повреждён или обрезан');
      }

      final entries = archive.where((f) => f.isFile).toList(growable: false);
      if (entries.isEmpty) {
        throw const RestoreException('архив пуст');
      }

      // Лимиты до распаковки: суммарный размер и compression ratio.
      var totalUncompressed = 0;
      final seenNames = <String>{};
      for (final entry in entries) {
        _validateEntryName(entry.name);
        // Case-insensitive коллизии: на Windows/macOS два таких имени
        // распаковались бы в один файл.
        if (!seenNames.add(entry.name.toLowerCase())) {
          throw const RestoreException('недопустимый путь внутри архива');
        }
        totalUncompressed += entry.size;
      }
      if (totalUncompressed > maxTotalUncompressedBytes) {
        throw const RestoreException('архив превышает допустимый размер');
      }
      if (totalUncompressed > ratioCheckFloorBytes &&
          archiveSize > 0 &&
          totalUncompressed > maxCompressionRatio * archiveSize) {
        throw const RestoreException('подозрительная степень сжатия архива');
      }

      await quarantine.create(recursive: true);
      final total = entries.length;
      var done = 0;
      final extractedHashes = <String, String>{};
      String? manifestJson;

      for (final entry in entries) {
        checkCancelled();
        if (entry.name == BackupFormat.manifestName) {
          final bytes = entry.readBytes();
          if (bytes == null) {
            throw const RestoreException('архив повреждён или обрезан');
          }
          manifestJson = utf8.decode(bytes, allowMalformed: false);
          onProgress?.call(++done, total);
          continue;
        }
        final localPath = _localPathFor(quarantine, entry.name);
        await Directory(p.dirname(localPath)).create(recursive: true);
        final out = OutputFileStream(localPath);
        try {
          entry.writeContent(out);
        } on Object {
          throw const RestoreException('архив повреждён или обрезан');
        } finally {
          await out.close();
        }
        final extracted = File(localPath);
        if (extracted.lengthSync() != entry.size) {
          throw const RestoreException('архив повреждён или обрезан');
        }
        extractedHashes[entry.name] = await _sha256Of(extracted);
        onProgress?.call(++done, total);
      }

      if (manifestJson == null) {
        throw const RestoreException('в архиве нет manifest.json');
      }
      final manifest = _decodeManifest(manifestJson);
      _verifyManifest(manifest.files, extractedHashes);

      final dbFile = File(p.join(quarantine.path, BackupFormat.databaseName));
      checkCancelled();
      final dbCounts = _verifyDatabase(dbFile, manifest.schemaVersion);

      final mediaDir = Directory(p.join(quarantine.path, 'media'));
      return RestoreCandidate(
        quarantineDir: quarantine,
        databaseFile: dbFile,
        mediaDir: mediaDir.existsSync() ? mediaDir : null,
        noteCount: dbCounts.notes,
        assetCount: extractedHashes.length - 1,
      );
    } finally {
      await input.close();
    }
  }

  /// Шаг 2: страховочная копия текущих данных и перенос кандидата на место.
  /// БД должна быть закрыта вызывающим кодом до вызова. Возвращает каталог
  /// страховочной копии. При ошибке откатывает рабочие данные и бросает.
  Future<Directory> apply(RestoreCandidate candidate) async {
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
    final safety = Directory(
      p.join(supportDir.path, 'backup-before-restore-$ts'),
    );
    await safety.create(recursive: true);

    // (from, to) выполненных переносов для отката в обратном порядке.
    final moves = <(String, String)>[];

    Future<void> move(String from, String to) async {
      await Directory(p.dirname(to)).create(recursive: true);
      final type = FileSystemEntity.typeSync(from, followLinks: false);
      if (type == FileSystemEntityType.notFound) return;
      if (type == FileSystemEntityType.directory) {
        await Directory(from).rename(to);
      } else {
        await File(from).rename(to);
      }
      moves.add((from, to));
    }

    String support(String name) => p.join(supportDir.path, name);
    String inSafety(String name) => p.join(safety.path, name);

    final dbSidecars = [
      databaseFileName,
      '$databaseFileName-wal',
      '$databaseFileName-shm',
    ];
    try {
      // 1. Текущие данные -> страховочная копия.
      for (final name in dbSidecars) {
        await move(support(name), inSafety(name));
      }
      await move(support('media'), inSafety('media'));

      // 2. Кандидат -> рабочие пути.
      await move(candidate.databaseFile.path, support(databaseFileName));
      final mediaDir = candidate.mediaDir;
      if (mediaDir != null) {
        await move(mediaDir.path, support('media'));
      } else {
        await Directory(support('media')).create(recursive: true);
      }
    } catch (error) {
      // Откат: рабочие данные возвращаются, ошибка уходит наружу.
      for (final (from, to) in moves.reversed) {
        try {
          final type = FileSystemEntity.typeSync(to, followLinks: false);
          if (type == FileSystemEntityType.directory) {
            await Directory(to).rename(from);
          } else if (type != FileSystemEntityType.notFound) {
            await File(to).rename(from);
          }
        } on FileSystemException {
          // Продолжаем откат остальных переносов.
        }
      }
      await _deleteQuietly(safety);
      throw const RestoreException(
        'не удалось заменить данные, выполнен откат',
      );
    }

    await _deleteQuietly(candidate.quarantineDir);
    return safety;
  }

  /// Отказ от подготовленного кандидата (отмена пользователем).
  Future<void> discard(RestoreCandidate candidate) =>
      _deleteQuietly(candidate.quarantineDir);

  // ---------- Проверки ----------

  /// Только имена из контракта контейнера; никакие `..`, абсолютные пути,
  /// backslash и спецсимволы не доходят до файловой системы.
  void _validateEntryName(String name) {
    if (name == BackupFormat.manifestName ||
        name == BackupFormat.databaseName) {
      return;
    }
    if (!name.startsWith(BackupFormat.mediaPrefix)) {
      throw const RestoreException('в архиве посторонний файл');
    }
    final segments = name.split('/');
    const safeSegment = r'^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$';
    for (final segment in segments) {
      if (segment == '..' ||
          segment == '.' ||
          segment.isEmpty ||
          segment.contains('\\') ||
          segment.contains(':') ||
          !RegExp(safeSegment).hasMatch(segment)) {
        throw const RestoreException('недопустимый путь внутри архива');
      }
      // Windows: завершающие точки/пробелы и зарезервированные имена
      // (CON, NUL, COM1…) недопустимы, в т.ч. с любым расширением.
      if (segment.endsWith('.') || segment.endsWith(' ')) {
        throw const RestoreException('недопустимый путь внутри архива');
      }
      final baseName = segment.split('.').first.toUpperCase();
      if (_windowsReservedNames.contains(baseName)) {
        throw const RestoreException('недопустимый путь внутри архива');
      }
    }
  }

  static const _windowsReservedNames = <String>{
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5',
    'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5',
    'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  String _localPathFor(Directory quarantine, String entryName) {
    final root = p.normalize(p.absolute(quarantine.path));
    final result = p.normalize(p.join(root, p.joinAll(entryName.split('/'))));
    if (!p.isWithin(root, result)) {
      throw const RestoreException('недопустимый путь внутри архива');
    }
    return result;
  }

  ({int schemaVersion, Map<String, String> files}) _decodeManifest(
    String json,
  ) {
    Object? raw;
    try {
      raw = jsonDecode(json);
    } on FormatException {
      throw const RestoreException('manifest.json повреждён');
    }
    if (raw is! Map<String, Object?> ||
        raw['format'] != BackupFormat.format ||
        raw['format_version'] != BackupFormat.formatVersion) {
      throw const RestoreException('это не резервная копия Потока');
    }
    final schemaVersion = raw['schema_version'];
    if (schemaVersion is! int) {
      throw const RestoreException('manifest.json повреждён');
    }
    final files = raw['files'];
    if (files is! Map<String, Object?>) {
      throw const RestoreException('manifest.json повреждён');
    }
    final typedFiles = files.map((key, value) {
      if (value is! String) {
        throw const RestoreException('manifest.json повреждён');
      }
      return MapEntry(key, value);
    });
    return (schemaVersion: schemaVersion, files: typedFiles);
  }

  void _verifyManifest(
    Map<String, String> expected,
    Map<String, String> extractedHashes,
  ) {
    if (!expected.containsKey(BackupFormat.databaseName)) {
      throw const RestoreException('в копии нет базы данных');
    }
    // Точное соответствие: ни лишних файлов, ни отсутствующих.
    if (expected.length != extractedHashes.length) {
      throw const RestoreException('состав архива не совпадает с manifest');
    }
    for (final entry in expected.entries) {
      final actual = extractedHashes[entry.key];
      if (actual == null) {
        throw const RestoreException('состав архива не совпадает с manifest');
      }
      if (actual != entry.value.toLowerCase()) {
        throw const RestoreException('контрольная сумма файла не совпадает');
      }
    }
  }

  /// Read-only открытие кандидата: целостность, ссылочная целостность и
  /// совпадение версии схемы. Миграций между версиями копий пока нет —
  /// при несовпадении честная ошибка (см. WP-06).
  ({int notes}) _verifyDatabase(File dbFile, int manifestSchemaVersion) {
    if (!dbFile.existsSync()) {
      throw const RestoreException('в копии нет базы данных');
    }
    if (manifestSchemaVersion != currentSchemaVersion) {
      throw const RestoreException('копия сделана другой версией приложения');
    }
    sqlite.Database database;
    try {
      database = sqlite.sqlite3.open(
        dbFile.path,
        mode: sqlite.OpenMode.readOnly,
      );
    } on Object {
      throw const RestoreException('база данных в копии не открывается');
    }
    try {
      final quick = database.select('PRAGMA quick_check');
      final quickOk = quick.length == 1 && quick.first.values.first == 'ok';
      if (!quickOk) {
        throw const RestoreException('база данных в копии повреждена');
      }
      final fkViolations = database.select('PRAGMA foreign_key_check');
      if (fkViolations.isNotEmpty) {
        throw const RestoreException(
          'база данных в копии нарушает целостность связей',
        );
      }
      final userVersion = database
          .select('PRAGMA user_version')
          .first
          .values
          .first;
      if (userVersion != currentSchemaVersion) {
        throw const RestoreException('копия сделана другой версией приложения');
      }
      final notes = database
          .select('SELECT COUNT(*) AS c FROM notes')
          .first
          .values
          .first;
      return (notes: notes is int ? notes : 0);
    } on RestoreException {
      rethrow;
    } on Object {
      throw const RestoreException('база данных в копии повреждена');
    } finally {
      database.close();
    }
  }

  static Future<String> _sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString().toLowerCase();

  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Мусор в quarantine не блокирует поток restore.
    }
  }
}
