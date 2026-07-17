import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/media_repair_service.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';

final _validM4a = <int>[
  0,
  0,
  0,
  24,
  0x66,
  0x74,
  0x79,
  0x70,
  0x4d,
  0x34,
  0x41,
  0x20,
  ...List.filled(52, 1),
];

void main() {
  late AppDatabase db;
  late Directory temp;
  late MediaStore media;
  late NotesService notes;
  late MediaRepairService repair;
  late FixedClock clock;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_media_repair_test');
    media = MediaStore(temp);
    clock = FixedClock(DateTime.utc(2026, 7, 17, 12));
    notes = NotesService(
      db: db,
      media: media,
      clock: clock,
      ids: SequentialIdGenerator(),
      deviceId: 'device-test',
    );
    repair = MediaRepairService(
      db: db,
      media: media,
      notes: notes,
      clock: clock,
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test(
    'ready audio becomes missing and is restored only with matching hash',
    () async {
      final staged = await notes.beginAudioNote(extension: 'm4a');
      await File(staged.stagingPath).writeAsBytes(_validM4a);
      await notes.finishAudioNote(
        staged,
        duration: const Duration(seconds: 2),
        codec: 'aac-lc',
        sampleRateHz: 44100,
        channels: 1,
      );
      final finalFile = File(media.absolutePath(staged.relativePath));
      final originalBytes = await finalFile.readAsBytes();
      await finalFile.delete();

      final missingReport = await repair.reconcile();
      var asset = await (db.select(
        db.mediaAssets,
      )..where((row) => row.id.equals(staged.assetId))).getSingle();
      expect(missingReport.markedMissing, 1);
      expect(asset.lifecycleState, AssetLifecycle.missing);

      await finalFile.writeAsBytes(List.filled(originalBytes.length, 2));
      final wrongHashReport = await repair.reconcile();
      asset = await (db.select(
        db.mediaAssets,
      )..where((row) => row.id.equals(staged.assetId))).getSingle();
      expect(wrongHashReport.restored, 0);
      expect(asset.lifecycleState, AssetLifecycle.missing);

      await finalFile.writeAsBytes(originalBytes);
      final restoredReport = await repair.reconcile();
      asset = await (db.select(
        db.mediaAssets,
      )..where((row) => row.id.equals(staged.assetId))).getSingle();
      expect(restoredReport.restored, 1);
      expect(asset.lifecycleState, AssetLifecycle.ready);
    },
  );

  test('startup completes audio left after atomic rename', () async {
    final staged = await notes.beginAudioNote(extension: 'm4a');
    await File(staged.stagingPath).writeAsBytes(_validM4a);
    await db
        .into(db.audioRecordings)
        .insert(
          AudioRecordingsCompanion.insert(
            assetId: staged.assetId,
            durationMs: 2000,
            codec: 'aac-lc',
            sampleRateHz: 44100,
            channels: 1,
            recordedAtUtc: clock.nowUtcMillis(),
          ),
        );
    await media.finalizeAudio(staged.relativePath);

    final report = await repair.reconcile();

    expect(report.recoveredAudio, 1);
    final asset = await (db.select(
      db.mediaAssets,
    )..where((row) => row.id.equals(staged.assetId))).getSingle();
    expect(asset.lifecycleState, AssetLifecycle.ready);
    expect(await notes.watchNotes().first, hasLength(1));
    expect(await db.select(db.noteEvents).get(), hasLength(1));
    expect(await db.select(db.operationJournal).get(), hasLength(1));
  });

  test(
    'stale incomplete audio staging is removed without visible note',
    () async {
      final staged = await notes.beginAudioNote(extension: 'm4a');
      await File(staged.stagingPath).writeAsBytes([1, 2, 3]);

      final report = await repair.reconcile(stagingGrace: Duration.zero);

      expect(report.discarded, 1);
      expect(await db.select(db.mediaAssets).get(), isEmpty);
      expect(await db.select(db.notes).get(), isEmpty);
      expect(File(staged.stagingPath).existsSync(), isFalse);
    },
  );
}
