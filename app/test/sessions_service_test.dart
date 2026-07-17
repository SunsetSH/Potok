import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/application/sessions_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late SessionsService sessions;
  late NotesService notes;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_sessions_test');
    clock = FixedClock(DateTime.utc(2026, 7, 17, 10));
    ids = SequentialIdGenerator();
    sessions = SessionsService(
      db: db,
      clock: clock,
      ids: ids,
      deviceId: 'device-test',
    );
    notes = NotesService(
      db: db,
      media: MediaStore(temp),
      clock: clock,
      ids: ids,
      deviceId: 'device-test',
    );
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'project-1',
            name: 'Проект',
            colorArgb: 0,
            createdAtUtc: 0,
            updatedAtUtc: 0,
          ),
        );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<Session> sessionById(String id) =>
      (db.select(db.sessions)..where((row) => row.id.equals(id))).getSingle();

  test('start enforces one active session in service and database', () async {
    await sessions.start(projectId: 'project-1', title: 'Встреча');
    await expectLater(
      sessions.start(projectId: 'project-1', title: 'Вторая'),
      throwsStateError,
    );
    await expectLater(
      db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 'manual-active',
              projectId: 'project-1',
              title: 'Обход сервиса',
              state: const Value(SessionState.active),
              startedAtUtc: 1,
              createdAtUtc: 1,
              updatedAtUtc: 1,
            ),
          ),
      throwsException,
    );

    final current = await db.select(db.sessions).getSingle();
    await sessions.pause(current);
    await expectLater(
      sessions.start(projectId: 'project-1', title: 'Пока первая на паузе'),
      throwsStateError,
    );
  });

  test(
    'pause, resume and complete use guarded revisions and journal',
    () async {
      final id = await sessions.start(projectId: 'project-1', title: 'Встреча');
      var session = await sessionById(id);
      final stale = session;
      await sessions.pause(session);
      session = await sessionById(id);
      expect(session.state, SessionState.paused);
      expect(session.revision, 2);
      await expectLater(sessions.pause(stale), throwsStateError);

      await sessions.resume(session);
      session = await sessionById(id);
      expect(session.state, SessionState.active);
      await sessions.complete(session);
      session = await sessionById(id);
      expect(session.state, SessionState.completed);
      expect(session.endedAtUtc, isNotNull);

      final operations = await db.select(db.operationJournal).get();
      expect(
        operations.map((row) => row.operationKind),
        containsAll([
          'session.start',
          'session.paused',
          'session.active',
          'session.complete',
        ]),
      );
    },
  );

  test('startup recovery always downgrades active to paused', () async {
    final id = await sessions.start(projectId: 'project-1', title: 'Встреча');
    expect(await sessions.recoverOnStartup(), 1);
    final recovered = await sessionById(id);
    expect(recovered.state, SessionState.paused);
    expect(recovered.revision, 2);
    expect(await sessions.recoverOnStartup(), 0);
  });

  test(
    'active session atomically supplies note project and session id',
    () async {
      final sessionId = await sessions.start(
        projectId: 'project-1',
        title: 'Тестирование',
      );
      final firstId = await notes.createTextNote(
        'первое наблюдение',
        sessionId: sessionId,
      );
      final first = await (db.select(
        db.notes,
      )..where((row) => row.id.equals(firstId))).getSingle();
      expect(first.projectId, 'project-1');
      expect(first.sessionId, sessionId);

      clock.advance(const Duration(minutes: 1));
      final secondId = await notes.createTextNote(
        'второе наблюдение',
        projectId: 'project-1',
        sessionId: sessionId,
      );
      expect(
        (await sessions.watchNotes(sessionId).first).map((note) => note.id),
        [firstId, secondId],
      );

      await sessions.pause(await sessionById(sessionId));
      await expectLater(
        notes.createTextNote('не должно сохраниться', sessionId: sessionId),
        throwsStateError,
      );
      expect(await db.notes.count().getSingle(), 2);
    },
  );

  test('session deletion keeps note and clears nullable link', () async {
    final sessionId = await sessions.start(
      projectId: 'project-1',
      title: 'Удаляемая',
    );
    final noteId = await notes.createTextNote(
      'наблюдение',
      sessionId: sessionId,
    );
    await (db.delete(
      db.sessions,
    )..where((row) => row.id.equals(sessionId))).go();
    final note = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(noteId))).getSingle();
    expect(note.sessionId, isNull);
  });

  test(
    'rename and soft delete keep notes and use optimistic journal',
    () async {
      final sessionId = await sessions.start(
        projectId: 'project-1',
        title: 'Черновое имя',
      );
      final noteId = await notes.createTextNote(
        'наблюдение',
        sessionId: sessionId,
      );
      final stale = await sessionById(sessionId);

      await sessions.rename(stale, 'Итоговое имя');
      var renamed = await sessionById(sessionId);
      expect(renamed.title, 'Итоговое имя');
      expect(renamed.revision, 2);
      await expectLater(sessions.rename(stale, 'Конфликт'), throwsStateError);

      await sessions.deleteKeepingNotes(renamed);
      renamed = await sessionById(sessionId);
      expect(renamed.deletedAtUtc, isNotNull);
      expect(renamed.state, SessionState.completed);
      expect(await sessions.watchSessions().first, isEmpty);
      final note = await (db.select(
        db.notes,
      )..where((row) => row.id.equals(noteId))).getSingle();
      expect(note.documentPlainText, 'наблюдение');
      expect(note.sessionId, sessionId);

      final operations = await db.select(db.operationJournal).get();
      expect(
        operations.map((row) => row.operationKind),
        containsAll(['session.rename', 'session.delete_keep_notes']),
      );
    },
  );
}
