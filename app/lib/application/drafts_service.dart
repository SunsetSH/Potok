import 'package:drift/drift.dart';

import '../domain/clock.dart';
import '../infrastructure/db/database.dart';

/// Черновики quick capture (FR-NOT-003/004): durable upsert по surface,
/// восстановление после process death, удаление в момент commit заметки.
/// Debounce (~500 ms) — ответственность UI-слоя.
class DraftsService {
  final AppDatabase db;
  final Clock clock;

  DraftsService({required this.db, required this.clock});

  Future<void> save(
    String surfaceId, {
    required String documentJson,
    String? noteId,
    String? projectId,
    String? tagIdsJson,
  }) async {
    await db.into(db.drafts).insertOnConflictUpdate(DraftsCompanion.insert(
          surfaceId: surfaceId,
          noteId: Value(noteId),
          documentJson: documentJson,
          projectId: Value(projectId),
          tagIdsJson: Value(tagIdsJson),
          updatedAtUtc: clock.nowUtcMillis(),
        ));
  }

  Future<Draft?> load(String surfaceId) =>
      (db.select(db.drafts)..where((d) => d.surfaceId.equals(surfaceId)))
          .getSingleOrNull();

  /// Идемпотентно: повторный clear после commit — no-op.
  Future<void> clear(String surfaceId) =>
      (db.delete(db.drafts)..where((d) => d.surfaceId.equals(surfaceId))).go();
}
