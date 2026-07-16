import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/types.dart';

part 'database.g.dart';

/// Vertical-slice schema (subset of ТЗ 0.7). All timestamps are UTC epoch
/// millis, IDs are UUIDv7 strings, soft delete via deletedAtUtc.
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get status =>
      text().map(const _NoteStatusConverter()).withDefault(const Constant('in_work'))();
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

class _NoteStatusConverter extends TypeConverter<NoteStatus, String> {
  const _NoteStatusConverter();

  @override
  NoteStatus fromSql(String fromDb) =>
      NoteStatus.values.firstWhere((s) => s.db == fromDb);

  @override
  String toSql(NoteStatus value) => value.db;
}

@DriftDatabase(tables: [Notes, MediaAssets, AudioRecordings, TranscriptRevisions])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open() => AppDatabase(
        driftDatabase(
          name: 'potok',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ),
      );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
