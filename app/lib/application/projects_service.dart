import 'package:drift/drift.dart';

import '../domain/clock.dart';
import '../domain/id_generator.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';

/// Use cases проектов (ТЗ 0.5.1, FR-PRJ). Удаление/архивация проекта не
/// уничтожает заметки: они переводятся в «Без проекта» той же транзакцией.
class ProjectsService {
  final AppDatabase db;
  final Clock clock;
  final IdGenerator ids;
  final String deviceId;

  ProjectsService({
    required this.db,
    required this.clock,
    required this.ids,
    required this.deviceId,
  });

  Stream<List<Project>> watchProjects({bool includeArchived = false}) {
    final query = db.select(db.projects)
      ..where((p) => p.deletedAtUtc.isNull());
    if (!includeArchived) {
      query.where((p) => p.isArchived.equals(false));
    }
    query.orderBy([
      (p) => OrderingTerm.desc(p.isPinned),
      (p) => OrderingTerm.asc(p.name),
    ]);
    return query.watch();
  }

  Future<String> createProject({
    required String name,
    required int colorArgb,
    String description = '',
    String? icon,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 120) {
      throw ArgumentError('project name must be 1..120 chars');
    }
    final id = ids.newId();
    final now = clock.nowUtcMillis();
    await db.into(db.projects).insert(ProjectsCompanion.insert(
          id: id,
          name: trimmed,
          description: Value(description),
          colorArgb: colorArgb,
          icon: Value(icon),
          createdAtUtc: now,
          updatedAtUtc: now,
        ));
    return id;
  }

  Future<void> rename(Project project, String newName) =>
      _update(project, ProjectsCompanion(name: Value(newName.trim())));

  Future<void> setPinned(Project project, bool pinned) =>
      _update(project, ProjectsCompanion(isPinned: Value(pinned)));

  Future<void> setArchived(Project project, bool archived) =>
      _update(project, ProjectsCompanion(isArchived: Value(archived)));

  /// Soft delete проекта; его живые заметки переходят в «Без проекта»
  /// с history-событием на каждую (ТЗ 0.5.1).
  Future<void> deleteProject(Project project) async {
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final updated = await (db.update(db.projects)
            ..where((p) =>
                p.id.equals(project.id) & p.revision.equals(project.revision)))
          .write(ProjectsCompanion(
        deletedAtUtc: Value(now),
        updatedAtUtc: Value(now),
        revision: Value(project.revision + 1),
      ));
      if (updated == 0) {
        throw StateError('project was modified concurrently, retry');
      }
      final orphans = await (db.select(db.notes)
            ..where((n) =>
                n.projectId.equals(project.id) & n.deletedAtUtc.isNull()))
          .get();
      for (final note in orphans) {
        await (db.update(db.notes)..where((n) => n.id.equals(note.id))).write(
          NotesCompanion(
            projectId: const Value(null),
            updatedAtUtc: Value(now),
            revision: Value(note.revision + 1),
          ),
        );
        await db.into(db.noteEvents).insert(NoteEventsCompanion.insert(
              id: ids.newId(),
              noteId: note.id,
              projectIdAtEvent: Value(project.id),
              kind: NoteEventKind.movedToProject,
              occurredAtUtc: now,
              deviceId: deviceId,
              payloadJson: const Value('{"to":null,"reason":"project_deleted"}'),
            ));
      }
    });
  }

  Future<void> _update(Project project, ProjectsCompanion changes) async {
    final now = clock.nowUtcMillis();
    final updated = await (db.update(db.projects)
          ..where((p) =>
              p.id.equals(project.id) & p.revision.equals(project.revision)))
        .write(changes.copyWith(
      updatedAtUtc: Value(now),
      revision: Value(project.revision + 1),
    ));
    if (updated == 0) {
      throw StateError('project was modified concurrently, retry');
    }
  }
}
