import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/application/projects_service.dart';
import 'package:potok/application/settings_service.dart';
import 'package:potok/application/tags_service.dart';
import 'package:potok/application/voice_classification_coordinator.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late NotesService notes;
  late ProjectsService projects;
  late TagsService tags;
  late SettingsService settings;
  late VoiceClassificationCoordinator coordinator;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_voice_classification');
    final clock = FixedClock(DateTime.utc(2026, 7, 22, 12));
    final ids = SequentialIdGenerator();
    notes = NotesService(
      db: db,
      media: MediaStore(temp),
      clock: clock,
      ids: ids,
      deviceId: 'device-test',
    );
    projects = ProjectsService(
      db: db,
      clock: clock,
      ids: ids,
      deviceId: 'device-test',
    );
    tags = TagsService(db: db, clock: clock, ids: ids, deviceId: 'device-test');
    settings = SettingsService(db: db);
    coordinator = VoiceClassificationCoordinator(
      settings: settings,
      notes: notes,
      projects: projects,
      tags: tags,
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<({String noteId, String projectId, String tagId})> seed() async {
    final noteId = await notes.createTextNote('Тестовая заметка');
    final projectId = await projects.createProject(
      name: 'Работа',
      colorArgb: 0xFF2364C4,
    );
    final tagId = await tags.createTag(
      name: 'Важно',
      colorArgb: 0xFFAD7A00,
      projectId: projectId,
    );
    return (noteId: noteId, projectId: projectId, tagId: tagId);
  }

  test('off ignores commands from a completed transcript', () async {
    final seeded = await seed();

    final result = await coordinator.processTranscript(
      seeded.noteId,
      'В проект Работа. Поставь тег важно',
    );

    expect(result, isNull);
    expect((await notes.getNote(seeded.noteId))!.projectId, isNull);
    expect(await tags.watchNoteTags(seeded.noteId).first, isEmpty);
  });

  test(
    'confirm resolves suggestion but does not mutate before approval',
    () async {
      final seeded = await seed();
      await settings.set(
        SettingsService.voiceClassificationModeKey,
        VoiceClassificationMode.confirm.storageValue,
      );

      final result = await coordinator.processTranscript(
        seeded.noteId,
        'Купить билеты в проект Работа. Поставь тег важно',
      );

      expect(
        result?.disposition,
        VoiceClassificationDisposition.confirmationRequired,
      );
      expect(result?.suggestion.project?.id, seeded.projectId);
      expect(result?.suggestion.tags.map((tag) => tag.id), [seeded.tagId]);
      expect((await notes.getNote(seeded.noteId))!.projectId, isNull);
      expect(await tags.watchNoteTags(seeded.noteId).first, isEmpty);
    },
  );

  test('auto moves note and assigns target-project tag immediately', () async {
    final seeded = await seed();
    await settings.set(
      SettingsService.voiceClassificationModeKey,
      VoiceClassificationMode.auto.storageValue,
    );

    final result = await coordinator.processTranscript(
      seeded.noteId,
      'Купить билеты в проект Работа. Поставь тег важно',
    );

    expect(result?.disposition, VoiceClassificationDisposition.applied);
    expect((await notes.getNote(seeded.noteId))!.projectId, seeded.projectId);
    expect(
      (await tags.watchNoteTags(seeded.noteId).first).map((tag) => tag.id),
      [seeded.tagId],
    );

    final duplicate = await coordinator.processTranscript(
      seeded.noteId,
      'Поставь тег важно. В проект Работа',
    );
    expect(
      duplicate,
      isNull,
      reason: 'live and final ASR must not notify twice',
    );
  });
}
