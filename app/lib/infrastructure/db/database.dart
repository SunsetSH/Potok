import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/types.dart';

part 'database.g.dart';

// Полная схема ТЗ 0.7 (ADR-004). Конвенции: UUIDv7-строки, UTC epoch millis,
// soft delete через deletedAtUtc, optimistic concurrency через revision.
// FTS5, частичные unique-индексы и триггеры — в schema.drift.

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get colorArgb => integer()();
  TextColumn get icon => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get createdAtUtc => integer()();
  IntColumn get updatedAtUtc => integer()();
  IntColumn get deletedAtUtc => integer().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get title => text().nullable()();
  TextColumn get status => text()
      .map(const NoteStatusConverter())
      .withDefault(const Constant('in_work'))();
  TextColumn get documentJson => text()();
  TextColumn get documentPlainText => text()();
  TextColumn get sourceKind => textEnum<SourceKind>()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  IntColumn get favoritedAtUtc => integer().nullable()();
  IntColumn get completedAtUtc => integer().nullable()();
  IntColumn get eventAtUtc => integer().nullable()();

  /// Служебная скрытая строка (image-драфт, staged-аудио): не показывается
  /// ни в списках, ни в корзине. Публикация снимает флаг.
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  IntColumn get createdAtUtc => integer()();
  IntColumn get updatedAtUtc => integer()();
  IntColumn get deletedAtUtc => integer().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get scope => textEnum<TagScope>()();

  /// null для global, обязателен для project (инвариант в домене + CHECK).
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get normalizedName => text()();
  IntColumn get colorArgb => integer()();
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAtUtc => integer()();
  IntColumn get updatedAtUtc => integer()();
  IntColumn get deletedAtUtc => integer().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK ((scope = 'global' AND project_id IS NULL) OR (scope = 'project' AND project_id IS NOT NULL))",
  ];
}

class NoteTags extends Table {
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get tagId => text().references(Tags, #id)();
  IntColumn get assignedAtUtc => integer()();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}

class MediaAssets extends Table {
  TextColumn get id => text()();
  TextColumn get ownerNoteId => text().references(Notes, #id)();
  TextColumn get kind => textEnum<AssetKind>()();
  TextColumn get relativePath => text()();
  TextColumn get mimeType => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get sha256 => text().nullable()();
  TextColumn get lifecycleState => textEnum<AssetLifecycle>()();
  IntColumn get createdAtUtc => integer()();
  IntColumn get updatedAtUtc => integer()();
  IntColumn get deletedAtUtc => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class AudioRecordings extends Table {
  TextColumn get assetId => text().references(MediaAssets, #id)();
  IntColumn get durationMs => integer()();
  TextColumn get codec => text()();
  IntColumn get sampleRateHz => integer()();
  IntColumn get channels => integer()();
  IntColumn get recordedAtUtc => integer()();

  @override
  Set<Column> get primaryKey => {assetId};
}

class TranscriptRevisions extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get audioAssetId => text().references(MediaAssets, #id)();
  TextColumn get engineId => text()();
  TextColumn get modelId => text()();
  TextColumn get language => text()();
  TextColumn get rawText => text().withDefault(const Constant(''))();
  TextColumn get segmentsJson => text().nullable()();
  TextColumn get state => textEnum<TranscriptState>()();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get createdAtUtc => integer()();
  IntColumn get acceptedAtUtc => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Audit-события (ТЗ 0.5.4): пишутся в одной транзакции с изменением.
class NoteEvents extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get projectIdAtEvent => text().nullable()();
  TextColumn get kind => textEnum<NoteEventKind>()();
  IntColumn get occurredAtUtc => integer()();
  TextColumn get deviceId => text()();
  TextColumn get payloadJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Черновики quick capture (FR-NOT-003/004): surface — точка ввода.
class Drafts extends Table {
  TextColumn get surfaceId => text()();
  TextColumn get noteId => text().nullable()();
  TextColumn get documentJson => text()();
  TextColumn get projectId => text().nullable()();
  TextColumn get tagIdsJson => text().nullable()();
  TextColumn get pendingMediaJson => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get updatedAtUtc => integer()();

  @override
  Set<Column> get primaryKey => {surfaceId};
}

/// Задел под sync (ADR-008): идемпотентность retry и будущий merge.
class OperationJournal extends Table {
  TextColumn get operationId => text()();
  TextColumn get deviceId => text()();
  TextColumn get entityKind => text()();
  TextColumn get entityId => text()();
  IntColumn get baseRevision => integer().nullable()();
  IntColumn get newRevision => integer().nullable()();
  TextColumn get operationKind => text()();
  IntColumn get occurredAtUtc => integer()();
  TextColumn get payloadJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {operationId};
}

/// Локальные метаданные установки (device_id и т.п.). Не синхронизируется.
class AppMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class SmartViews extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get definitionVersion => integer()();
  TextColumn get definitionJson => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAtUtc => integer()();
  IntColumn get updatedAtUtc => integer()();
  IntColumn get deletedAtUtc => integer().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteStatusConverter extends TypeConverter<NoteStatus, String> {
  const NoteStatusConverter();

  @override
  NoteStatus fromSql(String fromDb) => NoteStatus.values.firstWhere(
    (s) => s.db == fromDb,
    // Неизвестное значение (например, из будущей версии) не должно ронять
    // чтение всей строки — деградация до статуса по умолчанию.
    orElse: () => NoteStatus.inWork,
  );

  @override
  String toSql(NoteStatus value) => value.db;
}

@DriftDatabase(
  tables: [
    Projects,
    Notes,
    Tags,
    NoteTags,
    MediaAssets,
    AudioRecordings,
    TranscriptRevisions,
    NoteEvents,
    Drafts,
    OperationJournal,
    AppMeta,
    SmartViews,
  ],
  include: {'schema.drift'},
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open() => AppDatabase(
    driftDatabase(
      name: 'potok',
      native: DriftNativeOptions(
        shareAcrossIsolates: true,
        // Приватный каталог приложения, рядом с media (ТЗ 0.10.1);
        // дефолт drift_flutter — Documents, что для рабочих данных не место.
        databaseDirectory: getApplicationSupportDirectory,
      ),
    ),
  );

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(smartViews);
        await m.createIndex(idxNotesLiveCreated);
        await m.createIndex(idxNotesLiveUpdated);
        await m.createIndex(idxNotesLiveEvent);
        await m.createIndex(idxNotesLiveTitle);
        await m.createIndex(idxNotesTrashDeleted);
        // v1 used an FTS column alias that did not match the external-content
        // Notes column. Rebuild it additively so existing notes stay searchable.
        await customStatement('DROP TRIGGER IF EXISTS notes_fts_insert');
        await customStatement('DROP TRIGGER IF EXISTS notes_fts_delete');
        await customStatement('DROP TRIGGER IF EXISTS notes_fts_update');
        await customStatement('DROP TABLE IF EXISTS notes_fts');
        await customStatement('''
CREATE VIRTUAL TABLE notes_fts USING fts5(
  title,
  document_plain_text,
  content='notes',
  content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2'
)
''');
        await customStatement('''
CREATE TRIGGER notes_fts_insert AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts (rowid, title, document_plain_text)
  VALUES (new.rowid, coalesce(new.title, ''), new.document_plain_text);
END
''');
        await customStatement('''
CREATE TRIGGER notes_fts_delete AFTER DELETE ON notes BEGIN
  INSERT INTO notes_fts (
    notes_fts, rowid, title, document_plain_text
  ) VALUES (
    'delete', old.rowid, coalesce(old.title, ''), old.document_plain_text
  );
END
''');
        await customStatement('''
CREATE TRIGGER notes_fts_update AFTER UPDATE ON notes BEGIN
  INSERT INTO notes_fts (
    notes_fts, rowid, title, document_plain_text
  ) VALUES (
    'delete', old.rowid, coalesce(old.title, ''), old.document_plain_text
  );
  INSERT INTO notes_fts (rowid, title, document_plain_text)
  VALUES (new.rowid, coalesce(new.title, ''), new.document_plain_text);
END
''');
        await customStatement(
          "INSERT INTO notes_fts(notes_fts) VALUES('rebuild')",
        );
      }
      if (from == 2) {
        // ADR-010: remove the product Session entity while preserving every
        // note and media row. FTS is external-content and must be detached
        // while Drift recreates Notes without session_id.
        //
        // v4's is_hidden column must exist on the physical table *before*
        // TableMigration copies rows into the schema-matching shape below,
        // otherwise the generated INSERT selects a column the v2 table
        // never had.
        final hasIsHidden = await customSelect(
          "SELECT 1 FROM pragma_table_info('notes') WHERE name = 'is_hidden'",
        ).get();
        if (hasIsHidden.isEmpty) {
          await customStatement(
            'ALTER TABLE notes ADD COLUMN is_hidden INTEGER NOT NULL DEFAULT 0',
          );
        }
        await customStatement('DROP TRIGGER IF EXISTS notes_fts_insert');
        await customStatement('DROP TRIGGER IF EXISTS notes_fts_delete');
        await customStatement('DROP TRIGGER IF EXISTS notes_fts_update');
        await customStatement('DROP TABLE IF EXISTS notes_fts');
        await customStatement('DROP INDEX IF EXISTS idx_notes_session');
        await customStatement('DROP INDEX IF EXISTS idx_sessions_single_open');
        await m.alterTable(TableMigration(notes));
        await customStatement('DROP TABLE IF EXISTS sessions');
        await customStatement('''
CREATE VIRTUAL TABLE notes_fts USING fts5(
  title,
  document_plain_text,
  content='notes',
  content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2'
)
''');
        await customStatement('''
CREATE TRIGGER notes_fts_insert AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts (rowid, title, document_plain_text)
  VALUES (new.rowid, coalesce(new.title, ''), new.document_plain_text);
END
''');
        await customStatement('''
CREATE TRIGGER notes_fts_delete AFTER DELETE ON notes BEGIN
  INSERT INTO notes_fts (
    notes_fts, rowid, title, document_plain_text
  ) VALUES (
    'delete', old.rowid, coalesce(old.title, ''), old.document_plain_text
  );
END
''');
        await customStatement('''
CREATE TRIGGER notes_fts_update AFTER UPDATE ON notes BEGIN
  INSERT INTO notes_fts (
    notes_fts, rowid, title, document_plain_text
  ) VALUES (
    'delete', old.rowid, coalesce(old.title, ''), old.document_plain_text
  );
  INSERT INTO notes_fts (rowid, title, document_plain_text)
  VALUES (new.rowid, coalesce(new.title, ''), new.document_plain_text);
END
''');
        await customStatement(
          "INSERT INTO notes_fts(notes_fts) VALUES('rebuild')",
        );
      }
      if (from < 4) {
        // v4: явный флаг служебной скрытой строки вместо магического title.
        // Реентерабельно: колонка могла появиться при пересоздании notes
        // (alterTable в ветке from == 2) или при повторном прогоне миграции.
        final hasColumn = await customSelect(
          "SELECT 1 FROM pragma_table_info('notes') WHERE name = 'is_hidden'",
        ).get();
        if (hasColumn.isEmpty) {
          await m.addColumn(notes, notes.isHidden);
        }
        // Backfill существующих скрытых строк по прежним признакам:
        // image-драфты (магический title) и staged-аудио (скрытая заметка
        // со staging-ассетом). media_assets могла ещё не существовать на
        // очень старых версиях схемы (test fixtures до v1) — тогда
        // проверяем только признак title.
        final hasMediaAssets = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'media_assets'",
        ).get();
        if (hasMediaAssets.isNotEmpty) {
          await customStatement('''
UPDATE notes SET is_hidden = 1
WHERE deleted_at_utc IS NOT NULL
  AND (
    title = '__potok_image_draft__'
    OR EXISTS (
      SELECT 1 FROM media_assets a
      WHERE a.owner_note_id = notes.id
        AND a.kind = 'audio'
        AND a.lifecycle_state = 'staging'
    )
  )
''');
        } else {
          await customStatement('''
UPDATE notes SET is_hidden = 1
WHERE deleted_at_utc IS NOT NULL AND title = '__potok_image_draft__'
''');
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
