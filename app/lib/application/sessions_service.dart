import 'package:drift/drift.dart';

import '../domain/clock.dart';
import '../domain/id_generator.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';

class SessionsService {
  final AppDatabase db;
  final Clock clock;
  final IdGenerator ids;
  final String deviceId;

  SessionsService({
    required this.db,
    required this.clock,
    required this.ids,
    required this.deviceId,
  });

  Stream<List<Session>> watchSessions() {
    final query = db.select(db.sessions)
      ..where((session) => session.deletedAtUtc.isNull())
      ..orderBy([
        (session) => OrderingTerm.desc(session.startedAtUtc),
        (session) => OrderingTerm.desc(session.id),
      ]);
    return query.watch();
  }

  Stream<Session?> watchCurrent() {
    final query = db.select(db.sessions)
      ..where(
        (session) =>
            session.deletedAtUtc.isNull() &
            session.state.isInValues(const [
              SessionState.active,
              SessionState.paused,
            ]),
      )
      ..orderBy([
        (session) => OrderingTerm.desc(session.startedAtUtc),
        (session) => OrderingTerm.desc(session.id),
      ])
      ..limit(1);
    return query.watchSingleOrNull();
  }

  Stream<List<Note>> watchNotes(String sessionId) {
    final query = db.select(db.notes)
      ..where(
        (note) => note.sessionId.equals(sessionId) & note.deletedAtUtc.isNull(),
      )
      ..orderBy([
        (note) => OrderingTerm.asc(note.createdAtUtc),
        (note) => OrderingTerm.asc(note.id),
      ]);
    return query.watch();
  }

  Future<String> start({
    required String projectId,
    required String title,
  }) async {
    final normalizedTitle = _validateTitle(title);
    final id = ids.newId();
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final project =
          await (db.select(db.projects)..where(
                (row) => row.id.equals(projectId) & row.deletedAtUtc.isNull(),
              ))
              .getSingleOrNull();
      if (project == null) throw StateError('session project is unavailable');
      final existing =
          await (db.select(db.sessions)..where(
                (row) =>
                    row.state.isInValues(const [
                      SessionState.active,
                      SessionState.paused,
                    ]) &
                    row.deletedAtUtc.isNull(),
              ))
              .getSingleOrNull();
      if (existing != null) throw StateError('another session is unfinished');
      await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: id,
              projectId: projectId,
              title: normalizedTitle,
              state: const Value(SessionState.active),
              startedAtUtc: now,
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      await _journal(id, 'session.start', null, 1, now);
    });
    return id;
  }

  Future<void> pause(Session session) =>
      _transition(session, SessionState.active, SessionState.paused);

  Future<void> resume(Session session) async {
    await db.transaction(() async {
      final other =
          await (db.select(db.sessions)..where(
                (row) =>
                    row.id.equals(session.id).not() &
                    row.state.equalsValue(SessionState.active) &
                    row.deletedAtUtc.isNull(),
              ))
              .getSingleOrNull();
      if (other != null) throw StateError('another session is active');
      await _transitionInsideTransaction(
        session,
        SessionState.paused,
        SessionState.active,
      );
    });
  }

  Future<void> complete(Session session) async {
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final changed =
          await (db.update(db.sessions)..where(
                (row) =>
                    row.id.equals(session.id) &
                    row.revision.equals(session.revision) &
                    row.state.isInValues(const [
                      SessionState.active,
                      SessionState.paused,
                    ]),
              ))
              .write(
                SessionsCompanion(
                  state: const Value(SessionState.completed),
                  endedAtUtc: Value(now),
                  updatedAtUtc: Value(now),
                  revision: Value(session.revision + 1),
                ),
              );
      if (changed == 0) throw StateError('session transition conflict');
      await _journal(
        session.id,
        'session.complete',
        session.revision,
        session.revision + 1,
        now,
      );
    });
  }

  Future<void> rename(Session session, String title) async {
    final normalizedTitle = _validateTitle(title);
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final changed =
          await (db.update(db.sessions)..where(
                (row) =>
                    row.id.equals(session.id) &
                    row.revision.equals(session.revision) &
                    row.deletedAtUtc.isNull(),
              ))
              .write(
                SessionsCompanion(
                  title: Value(normalizedTitle),
                  updatedAtUtc: Value(now),
                  revision: Value(session.revision + 1),
                ),
              );
      if (changed == 0) throw StateError('session rename conflict');
      await _journal(
        session.id,
        'session.rename',
        session.revision,
        session.revision + 1,
        now,
      );
    });
  }

  /// Removes only the grouping context. Notes and their revisions are not
  /// touched; a later physical purge relies on ON DELETE SET NULL.
  Future<void> deleteKeepingNotes(Session session) async {
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final changed =
          await (db.update(db.sessions)..where(
                (row) =>
                    row.id.equals(session.id) &
                    row.revision.equals(session.revision) &
                    row.deletedAtUtc.isNull(),
              ))
              .write(
                SessionsCompanion(
                  state: const Value(SessionState.completed),
                  endedAtUtc: Value(session.endedAtUtc ?? now),
                  deletedAtUtc: Value(now),
                  updatedAtUtc: Value(now),
                  revision: Value(session.revision + 1),
                ),
              );
      if (changed == 0) throw StateError('session delete conflict');
      await _journal(
        session.id,
        'session.delete_keep_notes',
        session.revision,
        session.revision + 1,
        now,
      );
    });
  }

  /// Crash recovery is deliberately a state downgrade and never touches a
  /// recorder or microphone adapter.
  Future<int> recoverOnStartup() async {
    final active =
        await (db.select(db.sessions)..where(
              (row) =>
                  row.state.equalsValue(SessionState.active) &
                  row.deletedAtUtc.isNull(),
            ))
            .get();
    if (active.isEmpty) return 0;
    final now = clock.nowUtcMillis();
    var recovered = 0;
    await db.transaction(() async {
      for (final session in active) {
        final changed =
            await (db.update(db.sessions)..where(
                  (row) =>
                      row.id.equals(session.id) &
                      row.revision.equals(session.revision) &
                      row.state.equalsValue(SessionState.active),
                ))
                .write(
                  SessionsCompanion(
                    state: const Value(SessionState.paused),
                    updatedAtUtc: Value(now),
                    revision: Value(session.revision + 1),
                  ),
                );
        if (changed == 0) continue;
        recovered++;
        await _journal(
          session.id,
          'session.recover_paused',
          session.revision,
          session.revision + 1,
          now,
        );
      }
    });
    return recovered;
  }

  Future<void> _transition(
    Session session,
    SessionState from,
    SessionState to,
  ) => db.transaction(() => _transitionInsideTransaction(session, from, to));

  Future<void> _transitionInsideTransaction(
    Session session,
    SessionState from,
    SessionState to,
  ) async {
    final now = clock.nowUtcMillis();
    final changed =
        await (db.update(db.sessions)..where(
              (row) =>
                  row.id.equals(session.id) &
                  row.revision.equals(session.revision) &
                  row.state.equalsValue(from),
            ))
            .write(
              SessionsCompanion(
                state: Value(to),
                updatedAtUtc: Value(now),
                revision: Value(session.revision + 1),
              ),
            );
    if (changed == 0) throw StateError('session transition conflict');
    await _journal(
      session.id,
      'session.${to.name}',
      session.revision,
      session.revision + 1,
      now,
    );
  }

  static String _validateTitle(String value) {
    final title = value.trim();
    if (title.isEmpty || title.length > 200) {
      throw ArgumentError('session title must be 1..200 chars');
    }
    return title;
  }

  Future<void> _journal(
    String entityId,
    String operation,
    int? baseRevision,
    int newRevision,
    int at,
  ) => db
      .into(db.operationJournal)
      .insert(
        OperationJournalCompanion.insert(
          operationId: ids.newId(),
          deviceId: deviceId,
          entityKind: 'session',
          entityId: entityId,
          baseRevision: Value(baseRevision),
          newRevision: Value(newRevision),
          operationKind: operation,
          occurredAtUtc: at,
        ),
      );
}
