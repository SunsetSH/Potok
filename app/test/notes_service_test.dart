import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/document.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/asr/local_speech_recognizer.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';

class _FakeRecognizer implements LocalSpeechRecognizer {
  String nextText = 'распознанный текст';
  Object? nextError;

  @override
  String get engineId => 'fake';

  @override
  Future<TranscriptionResult> transcribeFile(
    String audioPath, {
    String languageHint = '',
  }) async {
    final error = nextError;
    if (error != null) throw error;
    return TranscriptionResult(
      text: nextText,
      modelId: 'fake-model',
      language: 'ru',
      audioDuration: const Duration(seconds: 1),
      processingTime: const Duration(milliseconds: 10),
    );
  }
}

void main() {
  late AppDatabase db;
  late Directory temp;
  late _FakeRecognizer recognizer;
  late NotesService service;
  late FixedClock clock;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_service_test');
    recognizer = _FakeRecognizer();
    clock = FixedClock(DateTime.utc(2026, 7, 16, 12));
    service = NotesService(
      db: db,
      media: MediaStore(temp),
      recognizer: recognizer,
      clock: clock,
      ids: SequentialIdGenerator(),
      deviceId: 'device-test',
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<StagedRecording> recordedNote() async {
    final staged = await service.beginAudioNote(extension: 'wav');
    await File(staged.stagingPath).writeAsBytes(List.filled(64, 7));
    await service.finishAudioNote(
      staged,
      duration: const Duration(seconds: 3),
      codec: 'pcm16-wav',
      sampleRateHz: 16000,
      channels: 1,
    );
    return staged;
  }

  group('text notes', () {
    test('createTextNote persists document envelope and projection', () async {
      await service.createTextNote('  привет  ');
      final notes = await service.watchNotes().first;
      expect(notes, hasLength(1));
      expect(notes.single.documentPlainText, 'привет');
      expect(notes.single.status, NoteStatus.inWork);
      expect(PotokDocument.decode(notes.single.documentJson).plainText, 'привет');
    });

    test('rejects empty text', () async {
      expect(() => service.createTextNote('   '), throwsArgumentError);
    });

    test('toggleDone flips status with optimistic revision bump', () async {
      await service.createTextNote('x');
      var note = (await service.watchNotes().first).single;
      await service.toggleDone(note);
      note = (await service.watchNotes().first).single;
      expect(note.status, NoteStatus.done);
      expect(note.completedAtUtc, isNotNull);
      expect(note.revision, 2);
    });
  });

  group('audio lifecycle', () {
    test('staged note is invisible until finalized', () async {
      final staged = await service.beginAudioNote(extension: 'wav');
      expect(await service.watchNotes().first, isEmpty);
      await File(staged.stagingPath).writeAsBytes([1, 2, 3]);
      await service.finishAudioNote(
        staged,
        duration: const Duration(seconds: 1),
        codec: 'pcm16-wav',
        sampleRateHz: 16000,
        channels: 1,
      );
      final notes = await service.watchNotes().first;
      expect(notes, hasLength(1));
      final asset = await service.watchReadyAudioAsset(staged.noteId).first;
      expect(asset, isNotNull);
      expect(asset!.lifecycleState, AssetLifecycle.ready);
      expect(asset.sha256, isNotNull);
    });

    test('finalize with missing bytes leaves no visible state', () async {
      final staged = await service.beginAudioNote(extension: 'wav');
      await expectLater(
        service.finishAudioNote(
          staged,
          duration: Duration.zero,
          codec: 'pcm16-wav',
          sampleRateHz: 16000,
          channels: 1,
        ),
        throwsA(isA<MediaFinalizeException>()),
      );
      expect(await service.watchNotes().first, isEmpty);
    });

    test('abort removes staged rows and bytes', () async {
      final staged = await service.beginAudioNote(extension: 'wav');
      await File(staged.stagingPath).writeAsBytes([1]);
      await service.abortAudioNote(staged);
      expect(await service.watchNotes().first, isEmpty);
      expect(File(staged.stagingPath).existsSync(), isFalse);
    });
  });

  group('transcription', () {
    test('success creates ready revision; accept appends paragraph once',
        () async {
      final staged = await recordedNote();
      final revision = await service.transcribe(staged.noteId, staged.assetId);
      expect(revision.state, TranscriptState.ready);
      expect(revision.rawText, 'распознанный текст');

      await service.acceptTranscript(staged.noteId, revision.id);
      final note = (await service.watchNotes().first).single;
      expect(note.documentPlainText, 'распознанный текст');
      expect(note.revision, 2);

      final revisions = await service.watchRevisions(staged.noteId).first;
      expect(revisions.single.acceptedAtUtc, isNotNull);
    });

    test('engine failure records failed revision and rethrows', () async {
      final staged = await recordedNote();
      recognizer.nextError = Exception('boom');
      await expectLater(
        service.transcribe(staged.noteId, staged.assetId),
        throwsException,
      );
      final revisions = await service.watchRevisions(staged.noteId).first;
      expect(revisions.single.state, TranscriptState.failed);
    });

    test('missing model records waiting_for_model', () async {
      final staged = await recordedNote();
      recognizer.nextError = const ModelUnavailableException('no model');
      await expectLater(
        service.transcribe(staged.noteId, staged.assetId),
        throwsA(isA<ModelUnavailableException>()),
      );
      final revisions = await service.watchRevisions(staged.noteId).first;
      expect(revisions.single.state, TranscriptState.waitingForModel);
    });

    test('re-transcription creates a second revision, originals kept',
        () async {
      final staged = await recordedNote();
      final first = await service.transcribe(staged.noteId, staged.assetId);
      recognizer.nextText = 'другая модель';
      final second = await service.transcribe(staged.noteId, staged.assetId);
      final revisions = await service.watchRevisions(staged.noteId).first;
      expect(revisions, hasLength(2));
      expect({first.id, second.id}, hasLength(2));
    });
  });

  group('history and operation journal (WP-01)', () {
    Future<List<NoteEvent>> eventsOf(String noteId) =>
        (db.select(db.noteEvents)..where((e) => e.noteId.equals(noteId)))
            .get();

    Future<List<OperationJournalData>> journalOf(String entityId) =>
        (db.select(db.operationJournal)
              ..where((o) => o.entityId.equals(entityId)))
            .get();

    test('createTextNote writes created event and journal atomically',
        () async {
      final id = await service.createTextNote('x');
      final events = await eventsOf(id);
      expect(events.single.kind, NoteEventKind.created);
      expect(events.single.deviceId, 'device-test');
      final journal = await journalOf(id);
      expect(journal.single.operationKind, 'note.create');
      expect(journal.single.newRevision, 1);
    });

    test('toggleDone writes completed then reopened events', () async {
      final id = await service.createTextNote('x');
      var note = (await service.watchNotes().first).single;
      await service.toggleDone(note);
      note = (await service.watchNotes().first).single;
      await service.toggleDone(note);
      final kinds = (await eventsOf(id)).map((e) => e.kind).toList();
      expect(
        kinds,
        containsAll([
          NoteEventKind.created,
          NoteEventKind.completed,
          NoteEventKind.reopened,
        ]),
      );
      final ops = (await journalOf(id)).map((o) => o.operationKind);
      expect(ops, containsAll(['note.complete', 'note.reopen']));
    });

    test('stale toggleDone (concurrent edit) fails without partial state',
        () async {
      final id = await service.createTextNote('x');
      final stale = (await service.watchNotes().first).single;
      await service.toggleDone(stale); // revision 1 -> 2
      await expectLater(service.toggleDone(stale), throwsStateError);
      final events = await eventsOf(id);
      // created + первый completed, второго события нет.
      expect(events, hasLength(2));
    });

    test('accepted transcript adds edited event', () async {
      final staged = await recordedNote();
      final revision =
          await service.transcribe(staged.noteId, staged.assetId);
      await service.acceptTranscript(staged.noteId, revision.id);
      final kinds = (await eventsOf(staged.noteId)).map((e) => e.kind);
      expect(kinds, contains(NoteEventKind.edited));
    });
  });

  group('full-text search (WP-01)', () {
    test('finds notes by word prefix in RU', () async {
      await service.createTextNote('Проверить восстановление черновика');
      await service.createTextNote('Совсем другая заметка');
      final hits = await service.searchNotes('восстановл');
      expect(hits, hasLength(1));
      expect(hits.single.documentPlainText, contains('восстановление'));
    });

    test('search is case-insensitive and follows accepted transcript',
        () async {
      final staged = await recordedNote();
      final revision =
          await service.transcribe(staged.noteId, staged.assetId);
      await service.acceptTranscript(staged.noteId, revision.id);
      final hits = await service.searchNotes('РАСПОЗНАННЫЙ');
      expect(hits.map((n) => n.id), contains(staged.noteId));
    });

    test('deleted notes are not searchable, quotes are neutralized',
        () async {
      await service.createTextNote('уникальное слово');
      expect(await service.searchNotes('"уникальное'), hasLength(1));
      expect(await service.searchNotes('   '), isEmpty);
    });
  });

  group('list filters (WP-02)', () {
    Future<void> insertProject(String id, String name) =>
        db.into(db.projects).insert(ProjectsCompanion.insert(
              id: id,
              name: name,
              colorArgb: 0xFF4E75DB,
              createdAtUtc: 0,
              updatedAtUtc: 0,
            ));

    Future<Note> noteById(String id) async =>
        (await service.watchNotes().first).firstWhere((n) => n.id == id);

    test('watchNotes(projectId) and onlyNoProject split notes by project',
        () async {
      await insertProject('p1', 'Проект');
      final inProjectId = await service.createTextNote('в проекте');
      await service.createTextNote('без проекта');
      await service.moveToProject(await noteById(inProjectId), 'p1');

      final inProject = await service.watchNotes(projectId: 'p1').first;
      expect(inProject.map((n) => n.id), [inProjectId]);

      final noProject =
          await service.watchNotes(onlyNoProject: true).first;
      expect(noProject.single.documentPlainText, 'без проекта');
    });

    test('watchNotes(onlyFavorites) follows the favorite flag', () async {
      final favoriteId = await service.createTextNote('избранная');
      await service.createTextNote('обычная');
      await service.setFavorite(await noteById(favoriteId), true);

      var favorites = await service.watchNotes(onlyFavorites: true).first;
      expect(favorites.single.id, favoriteId);

      await service.setFavorite(await noteById(favoriteId), false);
      favorites = await service.watchNotes(onlyFavorites: true).first;
      expect(favorites, isEmpty);
    });

    test('filtered lists exclude trashed notes', () async {
      await insertProject('p2', 'Другой');
      final id = await service.createTextNote('в корзину');
      await service.moveToProject(await noteById(id), 'p2');
      await service.setFavorite(await noteById(id), true);
      await service.moveToTrash(await noteById(id));

      expect(await service.watchNotes(projectId: 'p2').first, isEmpty);
      expect(await service.watchNotes(onlyFavorites: true).first, isEmpty);
      final trash = await service.watchTrash().first;
      expect(trash.map((n) => n.id), contains(id));
    });
  });

  group('schema invariants (WP-01)', () {
    test('duplicate global tag name is rejected by partial unique index',
        () async {
      Future<void> insertTag(String id, String name) =>
          db.into(db.tags).insert(TagsCompanion.insert(
                id: id,
                scope: TagScope.global,
                name: name,
                normalizedName: name.toLowerCase(),
                colorArgb: 0xFF000000,
                createdAtUtc: 0,
                updatedAtUtc: 0,
              ));
      await insertTag('t1', 'Вопрос');
      await expectLater(insertTag('t2', 'вопрос'), throwsException);
    });

    test('project-scoped tag requires project_id (CHECK)', () async {
      await expectLater(
        db.into(db.tags).insert(TagsCompanion.insert(
              id: 't3',
              scope: TagScope.project,
              name: 'x',
              normalizedName: 'x',
              colorArgb: 0,
              createdAtUtc: 0,
              updatedAtUtc: 0,
            )),
        throwsException,
      );
    });
  });
}
