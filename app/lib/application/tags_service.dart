import 'package:drift/drift.dart';

import '../domain/clock.dart';
import '../domain/id_generator.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';

/// Судьба project-тегов при переносе заметки в другой проект (ТЗ 0.5.2).
enum ProjectTagResolution { drop, convertToGlobal }

/// Use cases тегов (ТЗ 0.5.2). Цвет не единственный носитель смысла —
/// это ответственность UI; здесь инварианты scope и уникальности.
class TagsService {
  final AppDatabase db;
  final Clock clock;
  final IdGenerator ids;
  final String deviceId;

  TagsService({
    required this.db,
    required this.clock,
    required this.ids,
    required this.deviceId,
  });

  /// Предустановленные глобальные теги (ТЗ 0.5.2), первый запуск.
  static const presetTags = <(String, int)>[
    ('Вопрос', 0xFF2364C4),
    ('Риск', 0xFFB85C16),
    ('Дефект', 0xFFC53C4B),
    ('Требование', 0xFF1E8A8A),
    ('Решение', 0xFF23825E),
    ('Идея', 0xFF7656BD),
    ('Задача', 0xFF3457D5),
    ('Уточнить', 0xFF64707F),
    ('Блокер', 0xFF8F1D2C),
    ('Важно', 0xFFAD7A00),
  ];

  Future<void> seedPresetsIfEmpty() async {
    await db.transaction(() async {
      final count = await db.tags.count().getSingle();
      if (count > 0) return;
      final now = clock.nowUtcMillis();
      var order = 0;
      for (final (name, color) in presetTags) {
        await db
            .into(db.tags)
            .insert(
              TagsCompanion.insert(
                id: ids.newId(),
                scope: TagScope.global,
                name: name,
                normalizedName: normalizeName(name),
                colorArgb: color,
                sortOrder: Value(order++),
                createdAtUtc: now,
                updatedAtUtc: now,
              ),
            );
      }
    });
  }

  static String normalizeName(String name) => name.trim().toLowerCase();

  Stream<List<Tag>> watchTags({String? projectId}) {
    final query = db.select(db.tags)..where((t) => t.deletedAtUtc.isNull());
    if (projectId == null) {
      query.where((t) => t.projectId.isNull());
    } else {
      query.where((t) => t.projectId.isNull() | t.projectId.equals(projectId));
    }
    query.orderBy([
      (t) => OrderingTerm.asc(t.sortOrder),
      (t) => OrderingTerm.asc(t.normalizedName),
    ]);
    return query.watch();
  }

  Stream<List<Tag>> watchAllTags() {
    final query = db.select(db.tags)
      ..where((tag) => tag.deletedAtUtc.isNull())
      ..orderBy([
        (tag) => OrderingTerm.asc(tag.scope),
        (tag) => OrderingTerm.asc(tag.projectId),
        (tag) => OrderingTerm.asc(tag.sortOrder),
        (tag) => OrderingTerm.asc(tag.normalizedName),
      ]);
    return query.watch();
  }

  Stream<List<Tag>> watchNoteTags(String noteId) {
    final join = db.select(db.tags).join(
      [innerJoin(db.noteTags, db.noteTags.tagId.equalsExp(db.tags.id))],
    )..where(db.noteTags.noteId.equals(noteId) & db.tags.deletedAtUtc.isNull());
    return join.watch().map(
      (rows) => rows.map((r) => r.readTable(db.tags)).toList(growable: false),
    );
  }

  Future<String> createTag({
    required String name,
    required int colorArgb,
    String? projectId,
    String? icon,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 60) {
      throw ArgumentError('tag name must be 1..60 chars');
    }
    final normalized = normalizeName(trimmed);
    final id = ids.newId();
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      // Дружелюбная ошибка вместо SqliteException от unique-индекса.
      final duplicateQuery = db.select(db.tags)
        ..where(
          (row) =>
              row.normalizedName.equals(normalized) & row.deletedAtUtc.isNull(),
        );
      if (projectId == null) {
        duplicateQuery.where((row) => row.projectId.isNull());
      } else {
        duplicateQuery.where((row) => row.projectId.equals(projectId));
      }
      if (await duplicateQuery.getSingleOrNull() != null) {
        throw StateError('tag name already exists in this scope');
      }
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(
              id: id,
              scope: projectId == null ? TagScope.global : TagScope.project,
              projectId: Value(projectId),
              name: trimmed,
              normalizedName: normalized,
              colorArgb: colorArgb,
              icon: Value(icon),
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
    });
    return id;
  }

  /// Scope is intentionally immutable. Moving a tag between global/project
  /// scopes could invalidate existing note-tag links and needs a separate,
  /// explicit migration use case.
  Future<void> updateTag(
    Tag tag, {
    required String name,
    required int colorArgb,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 60) {
      throw ArgumentError('tag name must be 1..60 chars');
    }
    final normalized = normalizeName(trimmed);
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final duplicateQuery = db.select(db.tags)
        ..where(
          (row) =>
              row.id.isNotValue(tag.id) &
              row.normalizedName.equals(normalized) &
              row.deletedAtUtc.isNull(),
        );
      if (tag.projectId == null) {
        duplicateQuery.where((row) => row.projectId.isNull());
      } else {
        duplicateQuery.where((row) => row.projectId.equals(tag.projectId!));
      }
      if (await duplicateQuery.getSingleOrNull() != null) {
        throw StateError('tag name already exists in this scope');
      }
      final changed =
          await (db.update(db.tags)..where(
                (row) =>
                    row.id.equals(tag.id) &
                    row.revision.equals(tag.revision) &
                    row.deletedAtUtc.isNull(),
              ))
              .write(
                TagsCompanion(
                  name: Value(trimmed),
                  normalizedName: Value(normalized),
                  colorArgb: Value(colorArgb),
                  updatedAtUtc: Value(now),
                  revision: Value(tag.revision + 1),
                ),
              );
      if (changed == 0) {
        throw StateError('tag was modified concurrently, retry');
      }
      await db
          .into(db.operationJournal)
          .insert(
            OperationJournalCompanion.insert(
              operationId: ids.newId(),
              deviceId: deviceId,
              entityKind: 'tag',
              entityId: tag.id,
              baseRevision: Value(tag.revision),
              newRevision: Value(tag.revision + 1),
              operationKind: 'tag.updated',
              occurredAtUtc: now,
            ),
          );
    });
  }

  /// Назначение тега с проверкой scope: project-тег допустим только на
  /// заметке своего проекта. Пишет tagsChanged (ТЗ 0.5.4).
  Future<void> assignTag(String noteId, String tagId) async {
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final note = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(noteId))).getSingle();
      if (note.deletedAtUtc != null) {
        throw StateError('cannot tag a trashed note');
      }
      final tag = await (db.select(
        db.tags,
      )..where((t) => t.id.equals(tagId))).getSingle();
      if (tag.deletedAtUtc != null) {
        throw StateError('tag unavailable');
      }
      if (tag.scope == TagScope.project && tag.projectId != note.projectId) {
        throw StateError('project tag belongs to a different project');
      }
      final existing =
          await (db.select(db.noteTags)..where(
                (nt) => nt.noteId.equals(noteId) & nt.tagId.equals(tagId),
              ))
              .getSingleOrNull();
      if (existing != null) return; // идемпотентно
      await _bumpNoteRevision(note, now);
      await db
          .into(db.noteTags)
          .insert(
            NoteTagsCompanion.insert(
              noteId: noteId,
              tagId: tagId,
              assignedAtUtc: now,
            ),
          );
      await _tagsChangedEvent(note, now, '{"assigned":"$tagId"}');
      await _journalNote(note, 'note.tag_assign', now);
    });
  }

  Future<void> unassignTag(String noteId, String tagId) async {
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final note = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(noteId))).getSingle();
      final deleted = await (db.delete(
        db.noteTags,
      )..where((nt) => nt.noteId.equals(noteId) & nt.tagId.equals(tagId))).go();
      if (deleted > 0) {
        await _bumpNoteRevision(note, now);
        await _tagsChangedEvent(note, now, '{"unassigned":"$tagId"}');
        await _journalNote(note, 'note.tag_unassign', now);
      }
    });
  }

  Future<void> _bumpNoteRevision(Note note, int at) async {
    final changed =
        await (db.update(db.notes)..where(
              (row) =>
                  row.id.equals(note.id) & row.revision.equals(note.revision),
            ))
            .write(
              NotesCompanion(
                updatedAtUtc: Value(at),
                revision: Value(note.revision + 1),
              ),
            );
    if (changed == 0) throw StateError('note changed concurrently');
  }

  Future<void> _journalNote(Note note, String operationKind, int at) {
    return db
        .into(db.operationJournal)
        .insert(
          OperationJournalCompanion.insert(
            operationId: ids.newId(),
            deviceId: deviceId,
            entityKind: 'note',
            entityId: note.id,
            baseRevision: Value(note.revision),
            newRevision: Value(note.revision + 1),
            operationKind: operationKind,
            occurredAtUtc: at,
          ),
        );
  }

  Future<void> bulkAssignTag(Iterable<Note> selection, String tagId) async {
    final byId = <String, Note>{for (final note in selection) note.id: note};
    if (byId.isEmpty || byId.length > 500) {
      throw ArgumentError('bulk selection must contain 1..500 unique notes');
    }
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final tag =
          await (db.select(db.tags)..where(
                (row) => row.id.equals(tagId) & row.deletedAtUtc.isNull(),
              ))
              .getSingleOrNull();
      if (tag == null) throw StateError('tag unavailable');
      for (final note in byId.values) {
        if (tag.scope == TagScope.project && tag.projectId != note.projectId) {
          throw StateError('project tag does not match every selected note');
        }
        final existing =
            await (db.select(db.noteTags)..where(
                  (link) =>
                      link.noteId.equals(note.id) & link.tagId.equals(tagId),
                ))
                .getSingleOrNull();
        if (existing != null) continue;
        final changed =
            await (db.update(db.notes)..where(
                  (row) =>
                      row.id.equals(note.id) &
                      row.revision.equals(note.revision) &
                      row.deletedAtUtc.isNull(),
                ))
                .write(
                  NotesCompanion(
                    updatedAtUtc: Value(now),
                    revision: Value(note.revision + 1),
                  ),
                );
        if (changed == 0) throw StateError('bulk tag conflict');
        await db
            .into(db.noteTags)
            .insert(
              NoteTagsCompanion.insert(
                noteId: note.id,
                tagId: tagId,
                assignedAtUtc: now,
              ),
            );
        await _tagsChangedEvent(note, now, '{"assigned":"$tagId"}');
        await db
            .into(db.operationJournal)
            .insert(
              OperationJournalCompanion.insert(
                operationId: ids.newId(),
                deviceId: deviceId,
                entityKind: 'note',
                entityId: note.id,
                baseRevision: Value(note.revision),
                newRevision: Value(note.revision + 1),
                operationKind: 'note.bulk_tag_assign',
                occurredAtUtc: now,
              ),
            );
      }
    });
  }

  Future<void> _tagsChangedEvent(Note note, int at, String payload) {
    return db
        .into(db.noteEvents)
        .insert(
          NoteEventsCompanion.insert(
            id: ids.newId(),
            noteId: note.id,
            projectIdAtEvent: Value(note.projectId),
            kind: NoteEventKind.tagsChanged,
            occurredAtUtc: at,
            deviceId: deviceId,
            payloadJson: Value(payload),
          ),
        );
  }
}
