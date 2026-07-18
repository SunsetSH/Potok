import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/drafts_service.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/application/projects_service.dart';
import 'package:potok/application/tags_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/document.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late FixedClock clock;
  late NotesService notes;
  late ProjectsService projects;
  late TagsService tags;
  late DraftsService drafts;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_org_test');
    clock = FixedClock(DateTime.utc(2026, 7, 17, 9));
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
    drafts = DraftsService(db: db, clock: clock);
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<Note> noteById(String id) =>
      (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle();

  group('projects', () {
    test(
      'deleteProject moves live notes to «Без проекта» atomically',
      () async {
        final projectId = await projects.createProject(
          name: 'Мобильный банк',
          colorArgb: 0xFF4E75DB,
        );
        final noteId = await notes.createTextNote('в проекте');
        await notes.moveToProject(await noteById(noteId), projectId);

        final project = (await projects.watchProjects().first).single;
        await projects.deleteProject(project);

        expect(await projects.watchProjects().first, isEmpty);
        final note = await noteById(noteId);
        expect(note.projectId, isNull);
        expect(note.deletedAtUtc, isNull, reason: 'заметка не уничтожается');
        final events = await (db.select(
          db.noteEvents,
        )..where((e) => e.noteId.equals(noteId))).get();
        expect(
          events.map((e) => e.kind),
          contains(NoteEventKind.movedToProject),
        );
      },
    );

    test('empty and overlong names rejected', () async {
      expect(
        () => projects.createProject(name: '  ', colorArgb: 0),
        throwsArgumentError,
      );
      expect(
        () => projects.createProject(name: 'x' * 121, colorArgb: 0),
        throwsArgumentError,
      );
    });
  });

  group('tags scope invariants', () {
    test('seedPresetsIfEmpty creates 10 global tags once', () async {
      await tags.seedPresetsIfEmpty();
      await tags.seedPresetsIfEmpty();
      final all = await tags.watchTags().first;
      expect(all, hasLength(10));
      expect(all.every((t) => t.scope == TagScope.global), isTrue);
    });

    test('project tag cannot be assigned to note of another project', () async {
      final projectA = await projects.createProject(name: 'A', colorArgb: 0);
      final tagId = await tags.createTag(
        name: 'срочно',
        colorArgb: 0,
        projectId: projectA,
      );
      final noteId = await notes.createTextNote('без проекта');
      await expectLater(tags.assignTag(noteId, tagId), throwsStateError);
    });

    test('assign is idempotent and writes tagsChanged once', () async {
      final tagId = await tags.createTag(name: 'важно', colorArgb: 0);
      final noteId = await notes.createTextNote('x');
      await tags.assignTag(noteId, tagId);
      await tags.assignTag(noteId, tagId);
      final events =
          await (db.select(db.noteEvents)..where(
                (e) =>
                    e.noteId.equals(noteId) &
                    e.kind.equalsValue(NoteEventKind.tagsChanged),
              ))
              .get();
      expect(events, hasLength(1));
      expect(await tags.watchNoteTags(noteId).first, hasLength(1));
    });

    test('bulk tag assignment is atomic and bumps note revisions', () async {
      final tagId = await tags.createTag(name: 'массовый', colorArgb: 0);
      final firstId = await notes.createTextNote('a');
      final secondId = await notes.createTextNote('b');
      var selection = [await noteById(firstId), await noteById(secondId)];
      await (db.update(db.notes)..where((row) => row.id.equals(secondId)))
          .write(const NotesCompanion(revision: Value(2)));

      await expectLater(tags.bulkAssignTag(selection, tagId), throwsStateError);
      expect(await db.select(db.noteTags).get(), isEmpty);

      await (db.update(db.notes)..where((row) => row.id.equals(secondId)))
          .write(const NotesCompanion(revision: Value(1)));
      selection = [await noteById(firstId), await noteById(secondId)];
      await tags.bulkAssignTag(selection, tagId);
      expect(await db.select(db.noteTags).get(), hasLength(2));
      expect((await noteById(firstId)).revision, 2);
      expect((await noteById(secondId)).revision, 2);
    });

    test(
      'custom global/project tags can be renamed with optimistic revision',
      () async {
        final projectId = await projects.createProject(name: 'A', colorArgb: 0);
        await tags.createTag(name: 'global custom', colorArgb: 1);
        await tags.createTag(
          name: 'project custom',
          colorArgb: 2,
          projectId: projectId,
        );
        final all = await tags.watchAllTags().first;
        expect(all, hasLength(2));
        expect(all.map((tag) => tag.scope), {
          TagScope.global,
          TagScope.project,
        });

        final projectTag = all.singleWhere((tag) => tag.projectId == projectId);
        await tags.updateTag(
          projectTag,
          name: 'Переименован',
          colorArgb: 0xFF23825E,
        );
        final updated = (await tags.watchAllTags().first).singleWhere(
          (tag) => tag.id == projectTag.id,
        );
        expect(updated.name, 'Переименован');
        expect(updated.colorArgb, 0xFF23825E);
        expect(updated.scope, TagScope.project);
        expect(updated.revision, projectTag.revision + 1);
        await expectLater(
          tags.updateTag(projectTag, name: 'stale', colorArgb: 0),
          throwsStateError,
        );
        final journal =
            await (db.select(db.operationJournal)..where(
                  (row) =>
                      row.entityId.equals(projectTag.id) &
                      row.operationKind.equals('tag.updated'),
                ))
                .get();
        expect(journal, hasLength(1));
      },
    );

    test('tag rename preserves uniqueness inside its scope', () async {
      await tags.createTag(name: 'Один', colorArgb: 0);
      await tags.createTag(name: 'Два', colorArgb: 0);
      final all = await tags.watchAllTags().first;
      final second = all.singleWhere((tag) => tag.name == 'Два');
      await expectLater(
        tags.updateTag(second, name: ' один ', colorArgb: 0),
        throwsStateError,
      );
    });
  });

  group('move to project with project-tag conflicts (FR-MOV-005)', () {
    test('drop: project tag is removed from note', () async {
      final projectA = await projects.createProject(name: 'A', colorArgb: 0);
      final projectB = await projects.createProject(name: 'B', colorArgb: 0);
      final noteId = await notes.createTextNote('x');
      await notes.moveToProject(await noteById(noteId), projectA);
      final tagId = await tags.createTag(
        name: 'заказчик',
        colorArgb: 0,
        projectId: projectA,
      );
      await tags.assignTag(noteId, tagId);

      await notes.moveToProject(await noteById(noteId), projectB);

      expect((await noteById(noteId)).projectId, projectB);
      expect(await tags.watchNoteTags(noteId).first, isEmpty);
    });

    test('convertToGlobal: tag becomes global and stays on note', () async {
      final projectA = await projects.createProject(name: 'A', colorArgb: 0);
      final noteId = await notes.createTextNote('x');
      await notes.moveToProject(await noteById(noteId), projectA);
      final tagId = await tags.createTag(
        name: 'заказчик',
        colorArgb: 0,
        projectId: projectA,
      );
      await tags.assignTag(noteId, tagId);

      await notes.moveToProject(
        await noteById(noteId),
        null,
        resolution: ProjectTagResolution.convertToGlobal,
      );

      final remaining = await tags.watchNoteTags(noteId).first;
      expect(remaining.single.scope, TagScope.global);
      expect(remaining.single.projectId, isNull);
    });

    test('global tags survive move untouched', () async {
      final projectA = await projects.createProject(name: 'A', colorArgb: 0);
      final tagId = await tags.createTag(name: 'важно', colorArgb: 0);
      final noteId = await notes.createTextNote('x');
      await tags.assignTag(noteId, tagId);
      await notes.moveToProject(await noteById(noteId), projectA);
      expect(await tags.watchNoteTags(noteId).first, hasLength(1));
    });
  });

  group('trash', () {
    test('trash hides note, restore brings it back with events', () async {
      final noteId = await notes.createTextNote('x');
      await notes.moveToTrash(await noteById(noteId));
      expect(await notes.watchNotes().first, isEmpty);
      expect((await notes.watchTrash().first).single.id, noteId);

      await notes.restoreFromTrash(await noteById(noteId));
      expect((await notes.watchNotes().first).single.id, noteId);
      final kinds = (await (db.select(
        db.noteEvents,
      )..where((e) => e.noteId.equals(noteId))).get()).map((e) => e.kind);
      expect(
        kinds,
        containsAll([NoteEventKind.deleted, NoteEventKind.restored]),
      );
    });
  });

  group('drafts (FR-NOT-003/004)', () {
    test('save/load/clear round-trip, upsert overwrites', () async {
      final doc = PotokDocument.fromPlainText('черновик').encode();
      await drafts.save('quick-capture', documentJson: doc);
      clock.advance(const Duration(seconds: 1));
      final doc2 = PotokDocument.fromPlainText('черновик 2').encode();
      await drafts.save('quick-capture', documentJson: doc2);

      final restored = await drafts.load('quick-capture');
      expect(
        PotokDocument.decode(restored!.documentJson).plainText,
        'черновик 2',
      );

      await drafts.clear('quick-capture');
      await drafts.clear('quick-capture'); // идемпотентно
      expect(await drafts.load('quick-capture'), isNull);
    });
  });

  group('document editing', () {
    test(
      'updateDocument bumps revision, refreshes projection and FTS',
      () async {
        final noteId = await notes.createTextNote('старый текст');
        final note = await noteById(noteId);
        await notes.updateDocument(
          note,
          PotokDocument.fromPlainText('новейший текст'),
        );
        final updated = await noteById(noteId);
        expect(updated.documentPlainText, 'новейший текст');
        expect(updated.revision, 2);
        expect(await notes.searchNotes('новейш'), hasLength(1));
        expect(await notes.searchNotes('стар'), isEmpty);
      },
    );

    test('stale update fails and leaves document intact', () async {
      final noteId = await notes.createTextNote('текст');
      final stale = await noteById(noteId);
      await notes.updateDocument(stale, PotokDocument.fromPlainText('первый'));
      await expectLater(
        notes.updateDocument(stale, PotokDocument.fromPlainText('второй')),
        throwsStateError,
      );
      expect((await noteById(noteId)).documentPlainText, 'первый');
    });
  });
}
