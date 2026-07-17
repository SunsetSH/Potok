import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/storage_usage_service.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';
import 'package:potok/infrastructure/recording_platform.dart';

void main() {
  test('snapshot separates audio, images, trash and missing assets', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final temp = await Directory.systemTemp.createTemp('potok_usage_test');
    addTearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'note-active',
            documentJson: '{}',
            documentPlainText: '',
            sourceKind: SourceKind.keyboard,
            createdAtUtc: 1,
            updatedAtUtc: 1,
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'note-trash',
            documentJson: '{}',
            documentPlainText: '',
            sourceKind: SourceKind.keyboard,
            createdAtUtc: 1,
            updatedAtUtc: 1,
            deletedAtUtc: const Value(2),
          ),
        );
    await db.batch((batch) {
      batch.insertAll(db.mediaAssets, [
        _asset('audio', 'note-active', AssetKind.audio, 100),
        _asset('image', 'note-active', AssetKind.image, 50),
        _asset('trash', 'note-trash', AssetKind.audio, 25),
        _asset(
          'missing',
          'note-active',
          AssetKind.audio,
          999,
          lifecycle: AssetLifecycle.missing,
        ),
      ]);
    });
    final service = StorageUsageService(
      db: db,
      media: MediaStore(temp),
      platform: _FakeStoragePlatform(),
    );

    final usage = await service.snapshot();

    expect(usage.audioBytes, 125);
    expect(usage.imageBytes, 50);
    expect(usage.trashBytes, 25);
    expect(usage.missingCount, 1);
    expect(usage.managedBytes, 175);
    expect(usage.freeBytes, 123456);
  });
}

MediaAssetsCompanion _asset(
  String id,
  String noteId,
  AssetKind kind,
  int size, {
  AssetLifecycle lifecycle = AssetLifecycle.ready,
}) {
  return MediaAssetsCompanion.insert(
    id: id,
    ownerNoteId: noteId,
    kind: kind,
    relativePath: 'aa/$id.bin',
    mimeType: 'application/octet-stream',
    sizeBytes: Value(size),
    lifecycleState: lifecycle,
    createdAtUtc: 1,
    updatedAtUtc: 1,
  );
}

class _FakeStoragePlatform implements RecordingPlatformPort {
  @override
  Future<int?> freeBytes(String managedPath) async => 123456;

  @override
  Future<void> setRecordingActive(bool active) async {}
}
