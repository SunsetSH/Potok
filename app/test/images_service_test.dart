import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:potok/application/images_service.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/document.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late Directory mediaRoot;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late MediaStore media;
  late NotesService notes;
  late ImagesService images;
  late Note note;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_images_test');
    mediaRoot = Directory(p.join(temp.path, 'media'));
    clock = FixedClock(DateTime.utc(2026, 7, 17, 10));
    ids = SequentialIdGenerator();
    media = MediaStore(mediaRoot);
    notes = NotesService(
      db: db,
      media: media,
      clock: clock,
      ids: ids,
      deviceId: 'device-test',
    );
    images = ImagesService(db: db, media: media, clock: clock, ids: ids);
    final noteId = await notes.createTextNote('Заметка со скриншотом');
    note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(noteId))).getSingle();
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  File sourceFile(String name, List<int> bytes) =>
      File(p.join(temp.path, name))..writeAsBytesSync(bytes);

  test('attach publishes a managed ready image with hash and size', () async {
    final source = sourceFile('screen.png', const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      1,
      2,
      3,
    ]);

    final asset = await images.attachImage(note, source.path);

    expect(asset.kind, AssetKind.image);
    expect(asset.lifecycleState, AssetLifecycle.ready);
    expect(asset.mimeType, 'image/png');
    expect(asset.sizeBytes, 11);
    expect(asset.sha256, isNotEmpty);
    expect(File(media.absolutePath(asset.relativePath)).existsSync(), isTrue);
    expect(File(media.stagingPath(asset.relativePath)).existsSync(), isFalse);
    expect(
      (await images.resolveReadyImageFile(asset.id))?.path,
      media.absolutePath(asset.relativePath),
    );
  });

  test(
    'rejects extension spoofing before DB or filesystem publication',
    () async {
      final source = sourceFile('not-an-image.png', const [1, 2, 3, 4]);

      await expectLater(
        images.attachImage(note, source.path),
        throwsA(isA<ImageAttachException>()),
      );

      expect(await db.select(db.mediaAssets).get(), isEmpty);
      expect(mediaRoot.existsSync(), isFalse);
    },
  );

  test(
    'finalize failure compensates the staging row and partial file',
    () async {
      final source = sourceFile('screen.jpg', const [0xFF, 0xD8, 0xFF, 1]);
      final failingMedia = _FailingMediaStore(mediaRoot);
      final failingImages = ImagesService(
        db: db,
        media: failingMedia,
        clock: clock,
        ids: ids,
      );

      await expectLater(
        failingImages.attachImage(note, source.path),
        throwsA(isA<MediaFinalizeException>()),
      );

      expect(await db.select(db.mediaAssets).get(), isEmpty);
      final leftovers = mediaRoot.existsSync()
          ? mediaRoot
                .listSync(recursive: true)
                .whereType<File>()
                .toList(growable: false)
          : const <File>[];
      expect(leftovers, isEmpty);
    },
  );

  test('resolver returns null when ready bytes are missing', () async {
    final source = sourceFile('screen.webp', const [
      0x52,
      0x49,
      0x46,
      0x46,
      0,
      0,
      0,
      0,
      0x57,
      0x45,
      0x42,
      0x50,
    ]);
    final asset = await images.attachImage(note, source.path);
    File(media.absolutePath(asset.relativePath)).deleteSync();

    expect(await images.resolveReadyImageFile(asset.id), isNull);
  });

  test(
    'reconcile keeps references and tombstones old unreferenced images',
    () async {
      final keptSource = sourceFile('kept.png', const [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        1,
      ]);
      final orphanSource = sourceFile('orphan.jpg', const [
        0xFF,
        0xD8,
        0xFF,
        2,
      ]);
      final kept = await images.attachImage(note, keptSource.path);
      final orphan = await images.attachImage(note, orphanSource.path);
      final document = PotokDocument.fromDeltaOps([
        {
          'insert': {'image': 'asset://${kept.id}'},
          'attributes': {'alt': 'Сохранить', 'display': 'wide'},
        },
        {'insert': '\n'},
      ]);
      await notes.updateDocument(note, document);
      clock.advance(const Duration(days: 2));

      final report = await images.reconcileOrphanImages(
        gracePeriod: const Duration(days: 1),
      );

      expect(report.markedDeleted, 1);
      expect(report.filesRemoved, 1);
      expect(report.cleanupFailures, 0);
      expect(report.corruptDocuments, 0);
      expect(await images.resolveReadyImageFile(kept.id), isNotNull);
      expect(await images.resolveReadyImageFile(orphan.id), isNull);
      final orphanRow = await (db.select(
        db.mediaAssets,
      )..where((asset) => asset.id.equals(orphan.id))).getSingle();
      expect(orphanRow.lifecycleState, AssetLifecycle.deleted);
      expect(orphanRow.deletedAtUtc, clock.nowUtcMillis());
      expect(
        File(media.absolutePath(orphan.relativePath)).existsSync(),
        isFalse,
      );

      final repeated = await images.reconcileOrphanImages(
        gracePeriod: const Duration(days: 1),
      );
      expect(repeated.markedDeleted, 0);
      expect(repeated.filesRemoved, 0);
    },
  );

  test('corrupt document blocks orphan marking fail-safe', () async {
    final source = sourceFile('unknown.webp', const [
      0x52,
      0x49,
      0x46,
      0x46,
      0,
      0,
      0,
      0,
      0x57,
      0x45,
      0x42,
      0x50,
    ]);
    final asset = await images.attachImage(note, source.path);
    await (db.update(db.notes)..where((row) => row.id.equals(note.id))).write(
      const NotesCompanion(documentJson: Value('{broken')),
    );
    clock.advance(const Duration(days: 2));

    final report = await images.reconcileOrphanImages(
      gracePeriod: const Duration(days: 1),
    );

    expect(report.corruptDocuments, 1);
    expect(report.markedDeleted, 0);
    expect(await images.resolveReadyImageFile(asset.id), isNotNull);
  });
}

class _FailingMediaStore extends MediaStore {
  _FailingMediaStore(super.root);

  @override
  Future<({int sizeBytes, String sha256hex})> finalize(
    String relativePath,
  ) async {
    throw const MediaFinalizeException('injected failure');
  }
}
