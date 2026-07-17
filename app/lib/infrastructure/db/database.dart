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

class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get state =>
      textEnum<SessionState>().withDefault(const Constant('active'))();
  IntColumn get startedAtUtc => integer()();
  IntColumn get endedAtUtc => integer().nullable()();
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
  TextColumn get sessionId => text().nullable().references(
    Sessions,
    #id,
    onDelete: KeyAction.setNull,
  )();
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
  NoteStatus fromSql(String fromDb) =>
      NoteStatus.values.firstWhere((s) => s.db == fromDb);

  @override
  String toSql(NoteStatus value) => value.db;
}

@DriftDatabase(
  tables: [
    Projects,
    Sessions,
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(sessions);
        await m.addColumn(notes, notes.sessionId);
        await m.createTable(smartViews);
        await m.createIndex(idxNotesSession);
        await m.createIndex(idxNotesLiveCreated);
        await m.createIndex(idxNotesLiveUpdated);
        await m.createIndex(idxNotesLiveEvent);
        await m.createIndex(idxNotesLiveTitle);
        await m.createIndex(idxNotesTrashDeleted);
        await m.createIndex(idxSessionsSingleOpen);
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
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
