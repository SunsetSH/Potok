import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/note_list_query.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/document.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';

final _validWavBytes = <int>[
  0x52,
  0x49,
  0x46,
  0x46,
  36,
  0,
  0,
  0,
  0x57,
  0x41,
  0x56,
  0x45,
  ...List.filled(52, 7),
];

void main() {
  late AppDatabase db;
  late Directory temp;
  late NotesService service;
  late FixedClock clock;
  late SequentialIdGenerator ids;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_service_test');
    clock = FixedClock(DateTime.utc(2026, 7, 16, 12));
    ids = SequentialIdGenerator();
    service = NotesService(
      db: db,
      media: MediaStore(temp),
      clock: clock,
      ids: ids,
      deviceId: 'device-test',
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<StagedRecording> recordedNote() async {
    final staged = await service.beginAudioNote(extension: 'wav');
    await File(staged.stagingPath).writeAsBytes(_validWavBytes);
    await service.finishAudioNote(
      staged,
      duration: const Duration(seconds: 3),
      codec: 'pcm16-wav',
      sampleRateHz: 16000,
      channels: 1,
    );
    return staged;
  }

  /// Готовая ревизия «из очереди» (сама очередь тестируется отдельно):
  /// здесь проверяется только протокол принятия NotesService.
  Future<String> insertReadyRevision(
    String noteId,
    String assetId, {
    String text = 'распознанный текст',
  }) async {
    final id = ids.newId();
    await db
        .into(db.transcriptRevisions)
        .insert(
          TranscriptRevisionsCompanion.insert(
            id: id,
            noteId: noteId,
            audioAssetId: assetId,
            engineId: 'fake',
            modelId: 'fake-model',
            language: 'ru',
            rawText: Value(text),
            state: TranscriptState.ready,
            createdAtUtc: clock.nowUtcMillis(),
          ),
        );
    return id;
  }

  group('text notes', () {
    test('createTextNote persists document envelope and projection', () async {
      await service.createTextNote('  привет  ');
      final notes = await service.watchNotes().first;
      expect(notes, hasLength(1));
      expect(notes.single.title, 'привет');
      expect(notes.single.documentPlainText, 'привет');
      expect(notes.single.status, NoteStatus.inWork);
      expect(
        PotokDocument.decode(notes.single.documentJson).plainText,
        'привет',
      );
    });

    test('rejects empty text', () async {
      expect(() => service.createTextNote('   '), throwsArgumentError);
    });

    test(
      'automatic title follows edits until the user names the note',
      () async {
        await service.createTextNote('First automatic title');
        var note = (await service.watchNotes().first).single;

        await service.updateDocument(
          note,
          PotokDocument.fromPlainText('Second automatic title'),
        );
        note = (await service.watchNotes().first).single;
        expect(note.title, 'Second automatic title');

        await service.updateTitle(note, 'My fixed title');
        note = (await service.watchNotes().first).single;
        await service.updateDocument(
          note,
          PotokDocument.fromPlainText('Third document text'),
        );
        note = (await service.watchNotes().first).single;
        expect(note.title, 'My fixed title');
      },
    );

    test(
      'change stream emits distinct revisions for consecutive writes',
      () async {
        final expectation = expectLater(
          service.watchChanges().take(3),
          emitsInOrder([0, 1, 2]),
        );
        await Future<void>.delayed(Duration.zero);
        await service.createTextNote('one');
        await service.createTextNote('two');
        await expectation;
      },
    );

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
      await File(staged.stagingPath).writeAsBytes(_validWavBytes);
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

    test('corrupt audio is never published as ready', () async {
      final staged = await service.beginAudioNote(extension: 'm4a');
      await File(staged.stagingPath).writeAsBytes(List.filled(64, 7));

      await expectLater(
        service.finishAudioNote(
          staged,
          duration: const Duration(seconds: 1),
          codec: 'aac-lc',
          sampleRateHz: 44100,
          channels: 1,
        ),
        throwsA(isA<MediaFinalizeException>()),
      );

      expect(await service.watchNotes().first, isEmpty);
      expect(File(staged.stagingPath).existsSync(), isTrue);
      expect(
        File(
          temp.path + Platform.pathSeparator + staged.relativePath,
        ).existsSync(),
        isFalse,
      );
      await service.abortAudioNote(staged);
    });

    test('abort removes staged rows and bytes', () async {
      final staged = await service.beginAudioNote(extension: 'wav');
      await File(staged.stagingPath).writeAsBytes([1]);
      await service.abortAudioNote(staged);
      expect(await service.watchNotes().first, isEmpty);
      expect(File(staged.stagingPath).existsSync(), isFalse);
    });

    test(
      'existing note accepts multiple independent audio attachments',
      () async {
        await service.createTextNote('основной текст');
        var note = (await service.watchNotes().first).single;

        for (var index = 0; index < 2; index++) {
          final staged = await service.beginAudioAttachment(
            note,
            extension: 'wav',
          );
          await File(staged.stagingPath).writeAsBytes(_validWavBytes);
          await service.finishAudioNote(
            staged,
            duration: Duration(seconds: index + 1),
            codec: 'pcm16-wav',
            sampleRateHz: 16000,
            channels: 1,
          );
          note = (await service.watchNotes().first).single;
        }

        final assets = await service.watchAudioAssets(note.id).first;
        expect(assets, hasLength(2));
        expect(assets.map((asset) => asset.sha256), everyElement(isNotNull));
        expect(note.documentPlainText, 'основной текст');
        expect(note.revision, 3);
      },
    );

    test('audio deletion is soft until explicit purge', () async {
      await service.createTextNote('заметка');
      var note = (await service.watchNotes().first).single;
      final staged = await service.beginAudioAttachment(note, extension: 'wav');
      await File(staged.stagingPath).writeAsBytes(_validWavBytes);
      await service.finishAudioNote(
        staged,
        duration: const Duration(seconds: 1),
        codec: 'pcm16-wav',
        sampleRateHz: 16000,
        channels: 1,
      );
      note = (await service.watchNotes().first).single;
      var asset = (await service.watchAudioAssets(note.id).first).single;
      final finalFile = File(
        temp.path + Platform.pathSeparator + asset.relativePath,
      );
      expect(finalFile.existsSync(), isTrue);

      await service.moveAudioToTrash(note, asset);

      expect(await service.watchAudioAssets(note.id).first, isEmpty);
      asset = await (db.select(
        db.mediaAssets,
      )..where((row) => row.id.equals(asset.id))).getSingle();
      expect(asset.deletedAtUtc, isNotNull);
      expect(finalFile.existsSync(), isTrue);

      note = (await service.watchNotes().first).single;
      await service.restoreAudio(note, asset);
      asset = await (db.select(
        db.mediaAssets,
      )..where((row) => row.id.equals(asset.id))).getSingle();
      expect(asset.deletedAtUtc, isNull);
      expect(await service.watchAudioAssets(note.id).first, hasLength(1));

      note = (await service.watchNotes().first).single;
      await service.moveAudioToTrash(note, asset);
      asset = await (db.select(
        db.mediaAssets,
      )..where((row) => row.id.equals(asset.id))).getSingle();
      note = (await service.watchNotes().first).single;
      await service.purgeAudio(note, asset);
      expect(finalFile.existsSync(), isFalse);
      final tombstone = await db.select(db.mediaAssets).getSingle();
      expect(tombstone.lifecycleState, AssetLifecycle.deleted);
      expect(tombstone.sizeBytes, 0);
      expect(await db.select(db.audioRecordings).get(), isEmpty);
    });
  });

  group('trash purge (forever delete)', () {
    test('purgeNote refuses a note that is not trashed', () async {
      await service.createTextNote('active note');
      final note = (await service.watchNotes().first).single;
      await expectLater(service.purgeNote(note), throwsArgumentError);
    });

    test('purgeNote removes the note, its audio file and child rows', () async {
      final staged = await recordedNote();
      var note = (await service.watchNotes().first).single;
      final asset = (await service.watchAudioAssets(note.id).first).single;
      final revisionId = await insertReadyRevision(
        staged.noteId,
        staged.assetId,
      );
      final file = File(
        temp.path + Platform.pathSeparator + asset.relativePath,
      );
      expect(file.existsSync(), isTrue);

      await service.moveToTrash(note);
      note = (await service.watchTrash().first).single;
      await service.purgeNote(note);

      expect(file.existsSync(), isFalse);
      expect(await service.getNote(note.id), isNull);
      expect(await service.watchTrash().first, isEmpty);
      expect(
        await (db.select(
          db.mediaAssets,
        )..where((row) => row.id.equals(asset.id))).get(),
        isEmpty,
      );
      expect(
        await (db.select(
          db.transcriptRevisions,
        )..where((row) => row.id.equals(revisionId))).get(),
        isEmpty,
      );
      expect(
        await (db.select(
          db.noteEvents,
        )..where((row) => row.noteId.equals(note.id))).get(),
        isEmpty,
      );
    });

    test('purgeNotes bulk-deletes and is atomic on stale revision', () async {
      await service.createTextNote('a');
      await service.createTextNote('b');
      final notes = await service.watchNotes().first;
      for (final note in notes) {
        await service.moveToTrash(note);
      }
      var trashed = await service.watchTrash().first;
      expect(trashed, hasLength(2));

      await (db.update(db.notes)..where((row) => row.id.equals(trashed[0].id)))
          .write(NotesCompanion(revision: Value(trashed[0].revision + 1)));

      await expectLater(service.purgeNotes(trashed), throwsStateError);
      expect(await service.watchTrash().first, hasLength(2));

      trashed = await service.watchTrash().first;
      await service.purgeNotes(trashed);
      expect(await service.watchTrash().first, isEmpty);
    });
  });

  group('transcription acceptance', () {
    test('accept appends paragraph once and marks revision accepted', () async {
      final staged = await recordedNote();
      final revisionId = await insertReadyRevision(
        staged.noteId,
        staged.assetId,
      );

      await service.acceptTranscript(staged.noteId, revisionId);
      final note = (await service.watchNotes().first).single;
      expect(note.documentPlainText, 'распознанный текст');
      expect(note.revision, 2);

      final revisions = await service.watchRevisions(staged.noteId).first;
      expect(revisions.single.acceptedAtUtc, isNotNull);
    });

    test('accept of a non-ready revision is rejected', () async {
      final staged = await recordedNote();
      final revisionId = ids.newId();
      await db
          .into(db.transcriptRevisions)
          .insert(
            TranscriptRevisionsCompanion.insert(
              id: revisionId,
              noteId: staged.noteId,
              audioAssetId: staged.assetId,
              engineId: 'fake',
              modelId: '',
              language: '',
              state: TranscriptState.queued,
              createdAtUtc: clock.nowUtcMillis(),
            ),
          );
      await expectLater(
        service.acceptTranscript(staged.noteId, revisionId),
        throwsStateError,
      );
    });
  });

  group('history and operation journal (WP-01)', () {
    Future<List<NoteEvent>> eventsOf(String noteId) =>
        (db.select(db.noteEvents)..where((e) => e.noteId.equals(noteId))).get();

    Future<List<OperationJournalData>> journalOf(String entityId) => (db.select(
      db.operationJournal,
    )..where((o) => o.entityId.equals(entityId))).get();

    test(
      'createTextNote writes created event and journal atomically',
      () async {
        final id = await service.createTextNote('x');
        final events = await eventsOf(id);
        expect(events.single.kind, NoteEventKind.created);
        expect(events.single.deviceId, 'device-test');
        final journal = await journalOf(id);
        expect(journal.single.operationKind, 'note.create');
        expect(journal.single.newRevision, 1);
      },
    );

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

    test(
      'stale toggleDone (concurrent edit) fails without partial state',
      () async {
        final id = await service.createTextNote('x');
        final stale = (await service.watchNotes().first).single;
        await service.toggleDone(stale); // revision 1 -> 2
        await expectLater(service.toggleDone(stale), throwsStateError);
        final events = await eventsOf(id);
        // created + первый completed, второго события нет.
        expect(events, hasLength(2));
      },
    );

    test('accepted transcript adds edited event', () async {
      final staged = await recordedNote();
      final revisionId = await insertReadyRevision(
        staged.noteId,
        staged.assetId,
      );
      await service.acceptTranscript(staged.noteId, revisionId);
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

    test(
      'search is case-insensitive and follows accepted transcript',
      () async {
        final staged = await recordedNote();
        final revisionId = await insertReadyRevision(
          staged.noteId,
          staged.assetId,
        );
        await service.acceptTranscript(staged.noteId, revisionId);
        final hits = await service.searchNotes('РАСПОЗНАННЫЙ');
        expect(hits.map((n) => n.id), contains(staged.noteId));
      },
    );

    test('deleted notes are not searchable, quotes are neutralized', () async {
      await service.createTextNote('уникальное слово');
      expect(await service.searchNotes('"уникальное'), hasLength(1));
      expect(await service.searchNotes('   '), isEmpty);
    });

    test('finds notes by parameterized project and tag names', () async {
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'project-meta',
              name: 'OrionWorkspace',
              colorArgb: 0,
              createdAtUtc: 0,
              updatedAtUtc: 0,
            ),
          );
      final projectNote = await service.createTextNote(
        'unrelated body one',
        projectId: 'project-meta',
      );
      final taggedNote = await service.createTextNote('unrelated body two');
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(
              id: 'tag-meta',
              scope: TagScope.global,
              name: 'CriticalMarker',
              normalizedName: 'criticalmarker',
              colorArgb: 0,
              createdAtUtc: 0,
              updatedAtUtc: 0,
            ),
          );
      await db
          .into(db.noteTags)
          .insert(
            NoteTagsCompanion.insert(
              noteId: taggedNote,
              tagId: 'tag-meta',
              assignedAtUtc: 0,
            ),
          );

      expect(
        (await service.searchNotes('Orion')).map((note) => note.id),
        contains(projectNote),
      );
      expect(
        (await service.searchNotes('Critical')).map((note) => note.id),
        contains(taggedNote),
      );
      expect(await service.searchNotes(r'%_\'), isEmpty);
    });
  });

  group('list filters (WP-02)', () {
    Future<void> insertProject(String id, String name) => db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: id,
            name: name,
            colorArgb: 0xFF4E75DB,
            createdAtUtc: 0,
            updatedAtUtc: 0,
          ),
        );

    Future<Note> noteById(String id) async =>
        (await service.watchNotes().first).firstWhere((n) => n.id == id);

    test(
      'watchNotes(projectId) and onlyNoProject split notes by project',
      () async {
        await insertProject('p1', 'Проект');
        final inProjectId = await service.createTextNote('в проекте');
        await service.createTextNote('без проекта');
        await service.moveToProject(await noteById(inProjectId), 'p1');

        final inProject = await service.watchNotes(projectId: 'p1').first;
        expect(inProject.map((n) => n.id), [inProjectId]);

        final noProject = await service.watchNotes(onlyNoProject: true).first;
        expect(noProject.single.documentPlainText, 'без проекта');
      },
    );

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

  group('combined list query (WP-04)', () {
    Future<void> insertProject(String id, String name) => db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: id,
            name: name,
            colorArgb: 0xFF4E75DB,
            createdAtUtc: 0,
            updatedAtUtc: 0,
          ),
        );

    Future<void> insertNote({
      required String id,
      required String text,
      String? projectId,
      NoteStatus status = NoteStatus.inWork,
      bool favorite = false,
      int createdAt = 100,
      int? updatedAt,
      int? eventAt,
    }) => db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            projectId: Value(projectId),
            status: Value(status),
            documentJson: PotokDocument.fromPlainText(text).encode(),
            documentPlainText: text,
            sourceKind: SourceKind.keyboard,
            isFavorite: Value(favorite),
            createdAtUtc: createdAt,
            updatedAtUtc: updatedAt ?? createdAt,
            eventAtUtc: Value(eventAt),
          ),
        );

    Future<void> insertTag(String id) => db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(
            id: id,
            scope: TagScope.global,
            name: id,
            normalizedName: id,
            colorArgb: 0,
            createdAtUtc: 0,
            updatedAtUtc: 0,
          ),
        );

    Future<void> assign(String noteId, String tagId) => db
        .into(db.noteTags)
        .insert(
          NoteTagsCompanion.insert(
            noteId: noteId,
            tagId: tagId,
            assignedAtUtc: 0,
          ),
        );

    test('combines project/no-project, status, favorite and period', () async {
      await insertProject('p1', 'Альфа');
      await insertProject('p2', 'Бета');
      await insertNote(
        id: 'a',
        text: 'подходит',
        projectId: 'p1',
        favorite: true,
        createdAt: 200,
      );
      await insertNote(
        id: 'b',
        text: 'без проекта, но выполнено',
        status: NoteStatus.done,
        favorite: true,
        createdAt: 210,
      );
      await insertNote(
        id: 'c',
        text: 'другой проект',
        projectId: 'p2',
        favorite: true,
        createdAt: 205,
      );
      await insertNote(
        id: 'd',
        text: 'слишком поздно',
        favorite: true,
        createdAt: 500,
      );

      const filter = NoteListFilter(
        projectIds: {'p1'},
        includeNoProject: true,
        statuses: {NoteStatus.inWork},
        favoriteOnly: true,
        periodStartUtc: 150,
        periodEndUtcExclusive: 300,
      );
      final rows = await service.watchNotes(filter: filter).first;
      expect(rows.map((n) => n.id), ['a']);
    });

    test('matches selected tags in ANY and ALL modes', () async {
      await insertTag('t1');
      await insertTag('t2');
      await insertNote(id: 'a', text: 'оба');
      await insertNote(id: 'b', text: 'один');
      await insertNote(id: 'c', text: 'без тегов');
      await assign('a', 't1');
      await assign('a', 't2');
      await assign('b', 't1');

      final any = await service
          .watchNotes(
            filter: const NoteListFilter(
              tagIds: {'t2'},
              tagMatchMode: TagMatchMode.any,
            ),
          )
          .first;
      expect(any.map((n) => n.id), ['a']);

      final all = await service
          .watchNotes(
            filter: const NoteListFilter(
              tagIds: {'t1', 't2'},
              tagMatchMode: TagMatchMode.all,
            ),
          )
          .first;
      expect(all.map((n) => n.id), ['a']);
    });

    test('requires actual ready audio, image and transcript rows', () async {
      await insertNote(id: 'a', text: 'полный набор');
      await insertNote(id: 'b', text: 'нет вложений');
      await db
          .into(db.mediaAssets)
          .insert(
            MediaAssetsCompanion.insert(
              id: 'audio',
              ownerNoteId: 'a',
              kind: AssetKind.audio,
              relativePath: 'audio.m4a',
              mimeType: 'audio/mp4',
              lifecycleState: AssetLifecycle.ready,
              createdAtUtc: 0,
              updatedAtUtc: 0,
            ),
          );
      await db
          .into(db.mediaAssets)
          .insert(
            MediaAssetsCompanion.insert(
              id: 'image',
              ownerNoteId: 'a',
              kind: AssetKind.image,
              relativePath: 'image.png',
              mimeType: 'image/png',
              lifecycleState: AssetLifecycle.ready,
              createdAtUtc: 0,
              updatedAtUtc: 0,
            ),
          );
      await db
          .into(db.transcriptRevisions)
          .insert(
            TranscriptRevisionsCompanion.insert(
              id: 'transcript',
              noteId: 'a',
              audioAssetId: 'audio',
              engineId: 'fake',
              modelId: 'fake',
              language: 'ru',
              rawText: const Value('текст'),
              state: TranscriptState.ready,
              createdAtUtc: 0,
            ),
          );

      final rows = await service
          .watchNotes(
            filter: const NoteListFilter(
              requireAudio: true,
              requireImage: true,
              requireTranscript: true,
            ),
          )
          .first;
      expect(rows.map((n) => n.id), ['a']);
    });

    test('all allowlisted sorts use a stable id tie-breaker', () async {
      await insertProject('p-alpha', 'Альфа');
      await insertProject('p-beta', 'Бета');
      await insertNote(
        id: 'a',
        text: 'beta',
        projectId: 'p-beta',
        createdAt: 100,
        updatedAt: 300,
        eventAt: 200,
      );
      await insertNote(
        id: 'b',
        text: 'Alpha',
        projectId: 'p-alpha',
        createdAt: 100,
        updatedAt: 200,
        eventAt: 300,
      );
      await insertNote(id: 'c', text: 'gamma', createdAt: 50, updatedAt: 100);

      Future<List<String>> ordered(
        NoteSortField field,
        NoteSortDirection direction,
      ) async =>
          (await service
                  .watchNotes(
                    order: NoteListOrder(field: field, direction: direction),
                  )
                  .first)
              .map((n) => n.id)
              .toList();

      expect(
        await ordered(NoteSortField.createdAt, NoteSortDirection.descending),
        ['b', 'a', 'c'],
      );
      expect(
        await ordered(NoteSortField.updatedAt, NoteSortDirection.ascending),
        ['c', 'b', 'a'],
      );
      expect(
        await ordered(NoteSortField.eventAt, NoteSortDirection.ascending),
        ['c', 'a', 'b'],
      );
      expect(await ordered(NoteSortField.title, NoteSortDirection.ascending), [
        'b',
        'a',
        'c',
      ]);
      expect(
        await ordered(NoteSortField.project, NoteSortDirection.ascending),
        ['b', 'a', 'c'],
      );
    });

    test(
      'keyset pages match the complete order without gaps or duplicates',
      () async {
        await insertProject('p-alpha', 'Alpha');
        await insertProject('p-beta', 'Beta');
        await insertNote(
          id: 'a',
          text: 'same',
          projectId: 'p-alpha',
          createdAt: 100,
          updatedAt: 300,
          eventAt: 200,
        );
        await insertNote(
          id: 'b',
          text: 'Same',
          projectId: 'p-alpha',
          createdAt: 100,
          updatedAt: 300,
          eventAt: 200,
        );
        await insertNote(
          id: 'c',
          text: 'zeta',
          projectId: 'p-beta',
          createdAt: 90,
          updatedAt: 400,
          eventAt: 100,
        );
        await insertNote(id: 'd', text: 'none-a', createdAt: 80);
        await insertNote(id: 'e', text: 'none-b', createdAt: 70);

        for (final field in NoteSortField.values) {
          for (final direction in NoteSortDirection.values) {
            final order = NoteListOrder(field: field, direction: direction);
            final expected = (await service.watchNotes(order: order).first)
                .map((note) => note.id)
                .toList();
            final actual = <String>[];
            NoteListCursor? cursor;
            do {
              final page = await service.fetchNotesPage(
                order: order,
                after: cursor,
                pageSize: 2,
              );
              actual.addAll(page.notes.map((note) => note.id));
              cursor = page.nextCursor;
              if (!page.hasMore) break;
              expect(cursor, isNotNull);
            } while (true);

            expect(actual, expected, reason: '${field.name}/${direction.name}');
            expect(actual.toSet(), hasLength(actual.length));
          }
        }
      },
    );

    test(
      'bounded ID filtering and navigation aggregates stay SQL-side',
      () async {
        await insertProject('p1', 'Project');
        await insertNote(id: 'a', text: 'a', projectId: 'p1', favorite: true);
        await insertNote(id: 'b', text: 'b');
        await insertNote(id: 'c', text: 'c', projectId: 'p1');
        final c = await service.getNote('c');
        await service.moveToTrash(c!);

        final filtered = await service.filterNotesByIds(const {
          'a',
          'b',
          'missing',
        }, projectId: 'p1');
        expect(filtered.map((note) => note.id), ['a']);
        expect((await service.watchNote('b').first)?.id, 'b');

        final summary = await service.watchNavigationSummary().first;
        expect(summary.total, 2);
        expect(summary.noProject, 1);
        expect(summary.favorites, 1);
        expect(summary.trash, 1);
        expect(await service.watchProjectCounts().first, {'p1': 1});
      },
    );

    test(
      'trash uses stable keyset pages when deletion times are equal',
      () async {
        for (final id in const ['a', 'b', 'c', 'd', 'e']) {
          await insertNote(id: id, text: id);
          await service.moveToTrash((await service.getNote(id))!);
        }

        final ids = <String>[];
        NoteListCursor? cursor;
        do {
          final page = await service.fetchTrashPage(after: cursor, pageSize: 2);
          ids.addAll(page.notes.map((note) => note.id));
          cursor = page.nextCursor;
          if (!page.hasMore) break;
        } while (true);

        expect(ids, ['e', 'd', 'c', 'b', 'a']);
      },
    );

    test('bounded bulk mutations are atomic on stale revision', () async {
      await insertProject('p1', 'Project');
      await insertNote(id: 'a', text: 'a');
      await insertNote(id: 'b', text: 'b');
      final snapshot = await service.getNotesByIds(const {'a', 'b'});
      await (db.update(db.notes)..where((row) => row.id.equals('b'))).write(
        const NotesCompanion(revision: Value(2)),
      );

      await expectLater(
        service.bulkSetStatus(snapshot, NoteStatus.done),
        throwsStateError,
      );
      var rows = await service.getNotesByIds(const {'a', 'b'});
      expect(rows.map((note) => note.status), everyElement(NoteStatus.inWork));

      await (db.update(db.notes)..where((row) => row.id.equals('b'))).write(
        const NotesCompanion(revision: Value(1)),
      );
      rows = await service.getNotesByIds(const {'a', 'b'});
      await service.bulkSetStatus(rows, NoteStatus.done);
      rows = await service.getNotesByIds(const {'a', 'b'});
      expect(rows.map((note) => note.status), everyElement(NoteStatus.done));
      await service.bulkMoveToProject(rows, 'p1');
      rows = await service.getNotesByIds(const {'a', 'b'});
      expect(rows.map((note) => note.projectId), everyElement('p1'));
      await service.bulkMoveToTrash(rows);
      expect((await service.watchTrash().first), hasLength(2));
    });

    test('first page of 50000 notes stays within the 500 ms budget', () async {
      final document = PotokDocument.fromPlainText('load').encode();
      final rows = List.generate(
        50000,
        (index) => NotesCompanion.insert(
          id: 'load-${index.toString().padLeft(5, '0')}',
          documentJson: document,
          documentPlainText: 'load $index',
          sourceKind: SourceKind.keyboard,
          createdAtUtc: index,
          updatedAtUtc: index,
        ),
        growable: false,
      );
      await db.batch((batch) => batch.insertAll(db.notes, rows));

      final stopwatch = Stopwatch()..start();
      final page = await service.fetchNotesPage(pageSize: 50);
      stopwatch.stop();

      expect(page.notes, hasLength(50));
      expect(page.notes.first.id, 'load-49999');
      expect(page.hasMore, isTrue);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason: 'first keyset page must not scan/materialize all 50000 notes',
      );
    });

    test('rejects invalid period and more than twenty tags', () {
      expect(
        () => service.watchNotes(
          filter: const NoteListFilter(
            periodStartUtc: 20,
            periodEndUtcExclusive: 10,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => service.watchNotes(
          filter: NoteListFilter(tagIds: {for (var i = 0; i < 21; i++) 't$i'}),
        ),
        throwsArgumentError,
      );
    });
  });

  group('schema invariants (WP-01)', () {
    test(
      'duplicate global tag name is rejected by partial unique index',
      () async {
        Future<void> insertTag(String id, String name) => db
            .into(db.tags)
            .insert(
              TagsCompanion.insert(
                id: id,
                scope: TagScope.global,
                name: name,
                normalizedName: name.toLowerCase(),
                colorArgb: 0xFF000000,
                createdAtUtc: 0,
                updatedAtUtc: 0,
              ),
            );
        await insertTag('t1', 'Вопрос');
        await expectLater(insertTag('t2', 'вопрос'), throwsException);
      },
    );

    test('project-scoped tag requires project_id (CHECK)', () async {
      await expectLater(
        db
            .into(db.tags)
            .insert(
              TagsCompanion.insert(
                id: 't3',
                scope: TagScope.project,
                name: 'x',
                normalizedName: 'x',
                colorArgb: 0,
                createdAtUtc: 0,
                updatedAtUtc: 0,
              ),
            ),
        throwsException,
      );
    });
  });
}
