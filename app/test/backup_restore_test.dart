import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:potok/application/backup_service.dart';
import 'package:potok/application/restore_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/document.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';

// Реальные файловые БД: VACUUM INTO работает только с файлом.
void main() {
  late Directory root;
  late Directory supportA;
  late AppDatabase dbA;

  const mediaBytes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  final mediaSha = sha256.convert(mediaBytes).toString();

  AppDatabase openDb(Directory support) =>
      AppDatabase(NativeDatabase(File(p.join(support.path, 'potok.sqlite'))));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('potok_backup_test');
    supportA = Directory(p.join(root.path, 'a'))..createSync(recursive: true);
    dbA = openDb(supportA);
  });

  tearDown(() async {
    await dbA.close();
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Windows иногда держит handle долю секунды — не роняем тест.
    }
  });

  /// Проект + тег + заметка + ready-аудио с файлом на диске.
  Future<String> seed(AppDatabase db, Directory support) async {
    const now = 1000;
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'proj-1',
            name: 'Проект',
            colorArgb: 0xFF000000,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(
            id: 'tag-1',
            scope: TagScope.global,
            name: 'важно',
            normalizedName: 'важно',
            colorArgb: 0xFF112233,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
    final document = PotokDocument.fromPlainText('первая заметка');
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'note-1',
            projectId: const Value('proj-1'),
            documentJson: document.encode(),
            documentPlainText: document.plainText,
            sourceKind: SourceKind.keyboard,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
    await db
        .into(db.noteTags)
        .insert(
          NoteTagsCompanion.insert(
            noteId: 'note-1',
            tagId: 'tag-1',
            assignedAtUtc: now,
          ),
        );
    final media = MediaStore(Directory(p.join(support.path, 'media')));
    final relativePath = media.relativePathFor('asset0001', 'wav');
    await media.prepareStaging(relativePath);
    File(media.absolutePath(relativePath)).writeAsBytesSync(mediaBytes);
    await db
        .into(db.mediaAssets)
        .insert(
          MediaAssetsCompanion.insert(
            id: 'asset0001',
            ownerNoteId: 'note-1',
            kind: AssetKind.audio,
            relativePath: relativePath,
            mimeType: 'audio/wav',
            sizeBytes: const Value(10),
            sha256: Value(mediaSha),
            lifecycleState: AssetLifecycle.ready,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
    return relativePath;
  }

  Future<String> createBackup() async {
    final target = p.join(root.path, 'copy.potok-backup');
    final service = BackupService(
      db: dbA,
      media: MediaStore(Directory(p.join(supportA.path, 'media'))),
      clock: FixedClock(DateTime.utc(2026, 7, 17)),
    );
    await service.createBackup(targetPath: target);
    return target;
  }

  /// Второй "рабочий" каталог с собственными данными для restore поверх них.
  Future<(Directory, AppDatabase)> otherSupport() async {
    final support = Directory(p.join(root.path, 'b'))
      ..createSync(recursive: true);
    final db = openDb(support);
    const now = 2000;
    final document = PotokDocument.fromPlainText('чужая заметка');
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'note-b',
            documentJson: document.encode(),
            documentPlainText: document.plainText,
            sourceKind: SourceKind.keyboard,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
    return (support, db);
  }

  RestoreService restoreServiceFor(Directory support) => RestoreService(
    supportDir: support,
    currentSchemaVersion: dbA.schemaVersion,
  );

  /// Пересобирает валидный архив с изменениями (tamper-хелпер).
  Future<String> rewriteArchive(
    String source,
    String target, {
    List<int> Function(String name, List<int> bytes)? mapContent,
    String Function(String manifestJson)? mapManifest,
  }) async {
    final archive = ZipDecoder().decodeBytes(File(source).readAsBytesSync());
    final out = Archive();
    for (final entry in archive.where((f) => f.isFile)) {
      var bytes = entry.readBytes()!.toList();
      if (entry.name == 'manifest.json' && mapManifest != null) {
        bytes = utf8.encode(mapManifest(utf8.decode(bytes)));
      } else if (mapContent != null) {
        bytes = mapContent(entry.name, bytes);
      }
      out.add(ArchiveFile.bytes(entry.name, bytes));
    }
    File(target).writeAsBytesSync(ZipEncoder().encodeBytes(out));
    return target;
  }

  test('backup: манифест, снапшот и sha256 всех вложений', () async {
    final relativePath = await seed(dbA, supportA);
    final target = await createBackup();

    final archive = ZipDecoder().decodeBytes(File(target).readAsBytesSync());
    final names = archive.where((f) => f.isFile).map((f) => f.name).toSet();
    final mediaName = 'media/${relativePath.replaceAll('\\', '/')}';
    expect(names, {'manifest.json', 'database.sqlite', mediaName});

    final manifest =
        jsonDecode(
              utf8.decode(archive.find('manifest.json')!.readBytes()!),
            )
            as Map<String, Object?>;
    expect(manifest['format'], 'potok.backup');
    expect(manifest['format_version'], 1);
    expect(manifest['schema_version'], dbA.schemaVersion);
    final counts = manifest['counts'] as Map<String, Object?>;
    expect(counts['notes'], 1);
    expect(counts['projects'], 1);
    expect(counts['tags'], 1);
    expect(counts['assets'], 1);
    final files = manifest['files'] as Map<String, Object?>;
    expect(files[mediaName], mediaSha);
    final dbBytes = archive.find('database.sqlite')!.readBytes()!;
    expect(files['database.sqlite'], sha256.convert(dbBytes).toString());
    expect(
      sha256.convert(archive.find(mediaName)!.readBytes()!).toString(),
      mediaSha,
    );
  });

  test('round-trip: restore возвращает проекты/заметки/теги/медиа', () async {
    final relativePath = await seed(dbA, supportA);
    final target = await createBackup();

    final (supportB, dbB) = await otherSupport();
    final service = restoreServiceFor(supportB);
    final candidate = await service.prepare(target);
    expect(candidate.noteCount, 1);
    await dbB.close();
    final safety = await service.apply(candidate);

    // Страховочная копия текущих данных существует.
    expect(File(p.join(safety.path, 'potok.sqlite')).existsSync(), isTrue);

    final restored = openDb(supportB);
    try {
      final notes = await restored.select(restored.notes).get();
      expect(notes.single.id, 'note-1');
      expect(notes.single.documentPlainText, 'первая заметка');
      final projects = await restored.select(restored.projects).get();
      expect(projects.single.name, 'Проект');
      final tags = await restored.select(restored.tags).get();
      expect(tags.single.name, 'важно');
      final links = await restored.select(restored.noteTags).get();
      expect(links.single.tagId, 'tag-1');
      final assets = await restored.select(restored.mediaAssets).get();
      expect(assets.single.id, 'asset0001');
    } finally {
      await restored.close();
    }
    final mediaFile = File(p.join(supportB.path, 'media', relativePath));
    expect(mediaFile.existsSync(), isTrue);
    expect(
      sha256.convert(mediaFile.readAsBytesSync()).toString(),
      mediaSha,
    );
  });

  Future<void> expectRejectedAndUntouched(
    String archivePath, {
    Object? message,
  }) async {
    final (supportB, dbB) = await otherSupport();
    final service = restoreServiceFor(supportB);
    try {
      await expectLater(
        service.prepare(archivePath),
        throwsA(
          isA<RestoreException>().having(
            (e) => e.message,
            'message',
            message ?? anything,
          ),
        ),
      );
      // Рабочие данные не тронуты.
      final notes = await dbB.select(dbB.notes).get();
      expect(notes.single.id, 'note-b');
    } finally {
      await dbB.close();
    }
  }

  test('tampered database.sqlite отвергается по sha256', () async {
    await seed(dbA, supportA);
    final target = await createBackup();
    final tampered = await rewriteArchive(
      target,
      p.join(root.path, 'tampered.potok-backup'),
      mapContent: (name, bytes) {
        if (name == 'database.sqlite') bytes[100] ^= 0xFF;
        return bytes;
      },
    );
    await expectRejectedAndUntouched(
      tampered,
      message: contains('контрольная сумма'),
    );
  });

  test('манифест с неверным sha медиа отвергается', () async {
    await seed(dbA, supportA);
    final target = await createBackup();
    final bad = await rewriteArchive(
      target,
      p.join(root.path, 'bad-media-sha.potok-backup'),
      mapManifest: (json) {
        final manifest = jsonDecode(json) as Map<String, Object?>;
        final files = (manifest['files'] as Map<String, Object?>);
        for (final key in files.keys) {
          if (key.startsWith('media/')) {
            files[key] = '0' * 64;
          }
        }
        return jsonEncode(manifest);
      },
    );
    await expectRejectedAndUntouched(
      bad,
      message: contains('контрольная сумма'),
    );
  });

  test('path traversal в архиве отвергается', () async {
    final archive = Archive()
      ..add(ArchiveFile.string('../evil.txt', 'evil'))
      ..add(ArchiveFile.string('manifest.json', '{}'));
    final path = p.join(root.path, 'traversal.potok-backup');
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    await expectRejectedAndUntouched(path);
  });

  test('абсолютный путь и посторонние файлы отвергаются', () async {
    final archive = Archive()
      ..add(ArchiveFile.string(r'C:\evil.txt', 'evil'))
      ..add(ArchiveFile.string('manifest.json', '{}'));
    final path = p.join(root.path, 'absolute.potok-backup');
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    await expectRejectedAndUntouched(path);
  });

  test('truncated архив отвергается', () async {
    await seed(dbA, supportA);
    final target = await createBackup();
    final bytes = File(target).readAsBytesSync();
    final truncatedPath = p.join(root.path, 'truncated.potok-backup');
    File(truncatedPath).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
    await expectRejectedAndUntouched(truncatedPath);
  });

  test('копия другой версии схемы отвергается', () async {
    await seed(dbA, supportA);
    final target = await createBackup();
    final wrongVersion = await rewriteArchive(
      target,
      p.join(root.path, 'wrong-schema.potok-backup'),
      mapManifest: (json) {
        final manifest = jsonDecode(json) as Map<String, Object?>;
        manifest['schema_version'] = 99;
        return jsonEncode(manifest);
      },
    );
    await expectRejectedAndUntouched(
      wrongVersion,
      message: contains('другой версией'),
    );
  });

  test('отмена backup не оставляет временных файлов', () async {
    await seed(dbA, supportA);
    final target = p.join(root.path, 'cancelled.potok-backup');
    final service = BackupService(
      db: dbA,
      media: MediaStore(Directory(p.join(supportA.path, 'media'))),
      clock: FixedClock(DateTime.utc(2026, 7, 17)),
    );
    await expectLater(
      service.createBackup(targetPath: target, isCancelled: () => true),
      throwsA(isA<BackupCancelled>()),
    );
    expect(File(target).existsSync(), isFalse);
    final leftovers = Directory(root.path)
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('cancelled'));
    expect(leftovers, isEmpty);
  });
}
