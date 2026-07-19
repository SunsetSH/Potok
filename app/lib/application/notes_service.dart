import 'package:drift/drift.dart';

import '../domain/clock.dart';
import '../domain/document.dart';
import '../domain/id_generator.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/media_store.dart';
import 'local_title_generator.dart';
import 'note_list_query.dart';
import 'tags_service.dart';

/// Use cases заметок. Каждая мутация — одна транзакция: изменение сущности,
/// NoteEvent и OperationJournal фиксируются вместе или не фиксируются вовсе
/// (ТЗ 0.5.4, 0.9).
class NotesService {
  final AppDatabase db;
  final MediaStore media;
  final Clock clock;
  final IdGenerator ids;
  final String deviceId;
  final LocalTitleGenerator titleGenerator;

  NotesService({
    required this.db,
    required this.media,
    required this.clock,
    required this.ids,
    required this.deviceId,
    this.titleGenerator = const LocalTitleGenerator(),
  });

  // ---------- Queries ----------

  /// Живые заметки. Фильтры разделов (WP-02): проект, «Без проекта»,
  /// «Избранное». [projectId] и [onlyNoProject] взаимоисключающие.
  Stream<List<Note>> watchNotes({
    String? projectId,
    bool onlyNoProject = false,
    bool onlyFavorites = false,
    NoteListFilter filter = const NoteListFilter(),
    NoteListOrder order = const NoteListOrder(),
  }) {
    final query = _createNotesQuery(
      projectId: projectId,
      onlyNoProject: onlyNoProject,
      onlyFavorites: onlyFavorites,
      filter: filter,
      order: order,
    );
    return query.watch().map(
      (rows) =>
          rows.map((row) => row.readTable(db.notes)).toList(growable: false),
    );
  }

  Future<NoteListPage> fetchNotesPage({
    String? projectId,
    bool onlyNoProject = false,
    bool onlyFavorites = false,
    NoteListFilter filter = const NoteListFilter(),
    NoteListOrder order = const NoteListOrder(),
    NoteListCursor? after,
    int pageSize = 50,
  }) async {
    if (pageSize < 1 || pageSize > 200) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be from 1 to 200');
    }
    final query = _createNotesQuery(
      projectId: projectId,
      onlyNoProject: onlyNoProject,
      onlyFavorites: onlyFavorites,
      filter: filter,
      order: order,
    );
    if (after != null) {
      query.where(_cursorPredicate(after, order));
    }
    query.limit(pageSize + 1);
    final rows = await query.get();
    final hasMore = rows.length > pageSize;
    final visibleRows = hasMore ? rows.take(pageSize).toList() : rows;
    final notes = visibleRows
        .map((row) => row.readTable(db.notes))
        .toList(growable: false);
    NoteListCursor? nextCursor;
    if (hasMore && visibleRows.isNotEmpty) {
      final row = visibleRows.last;
      final note = row.readTable(db.notes);
      final project = row.readTableOrNull(db.projects);
      nextCursor = NoteListCursor(
        sortValue: _cursorValue(note, project, order.field),
        id: note.id,
      );
    }
    return NoteListPage(notes: notes, nextCursor: nextCursor, hasMore: hasMore);
  }

  /// Applies the current section/filter to an already bounded set of FTS hits.
  /// Search never loads the whole section merely to intersect IDs.
  Future<List<Note>> filterNotesByIds(
    Iterable<String> ids, {
    String? projectId,
    bool onlyNoProject = false,
    bool onlyFavorites = false,
    NoteListFilter filter = const NoteListFilter(),
    NoteListOrder order = const NoteListOrder(),
  }) async {
    final bounded = ids.toSet();
    if (bounded.isEmpty) return const [];
    if (bounded.length > 200) {
      throw ArgumentError.value(bounded.length, 'ids', 'at most 200 IDs');
    }
    final query = _createNotesQuery(
      projectId: projectId,
      onlyNoProject: onlyNoProject,
      onlyFavorites: onlyFavorites,
      filter: filter,
      order: order,
    )..where(db.notes.id.isIn(bounded));
    final rows = await query.get();
    return rows.map((row) => row.readTable(db.notes)).toList(growable: false);
  }

  Future<Note?> getNote(String id) {
    return (db.select(
      db.notes,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Future<List<Note>> getNotesByIds(Iterable<String> ids) async {
    final bounded = ids.toSet();
    if (bounded.isEmpty || bounded.length > 500) {
      throw ArgumentError('selection must contain 1..500 unique IDs');
    }
    return (db.select(db.notes)..where((row) => row.id.isIn(bounded))).get();
  }

  Stream<Note?> watchNote(String id) {
    return (db.select(
      db.notes,
    )..where((row) => row.id.equals(id))).watchSingleOrNull();
  }

  Stream<NavigationSummary> watchNavigationSummary() {
    return db
        .customSelect(
          '''
SELECT
  SUM(CASE WHEN deleted_at_utc IS NULL THEN 1 ELSE 0 END) AS total_count,
  SUM(CASE WHEN deleted_at_utc IS NULL AND project_id IS NULL THEN 1 ELSE 0 END) AS no_project_count,
  SUM(CASE WHEN deleted_at_utc IS NULL AND is_favorite = 1 THEN 1 ELSE 0 END) AS favorite_count,
  SUM(CASE WHEN deleted_at_utc IS NOT NULL AND is_hidden = 0 THEN 1 ELSE 0 END) AS trash_count
FROM notes
''',
          readsFrom: {db.notes},
        )
        .watchSingle()
        .map(
          (row) => NavigationSummary(
            total: row.read<int?>('total_count') ?? 0,
            noProject: row.read<int?>('no_project_count') ?? 0,
            favorites: row.read<int?>('favorite_count') ?? 0,
            trash: row.read<int?>('trash_count') ?? 0,
          ),
        );
  }

  Stream<Map<String, int>> watchProjectCounts() {
    return db
        .customSelect(
          '''
SELECT project_id, COUNT(*) AS note_count
FROM notes
WHERE deleted_at_utc IS NULL AND project_id IS NOT NULL
GROUP BY project_id
''',
          readsFrom: {db.notes},
        )
        .watch()
        .map(
          (rows) => Map.unmodifiable({
            for (final row in rows)
              row.read<String>('project_id'): row.read<int>('note_count'),
          }),
        );
  }

  /// Lightweight invalidation stream. Drift re-runs it after every Notes
  /// table mutation without materializing note rows.
  Stream<int> watchChanges() async* {
    var revision = 0;
    await for (final _
        in db.customSelect('SELECT 1', readsFrom: {db.notes}).watch()) {
      yield revision++;
    }
  }

  JoinedSelectStatement<HasResultSet, dynamic> _createNotesQuery({
    String? projectId,
    bool onlyNoProject = false,
    bool onlyFavorites = false,
    NoteListFilter filter = const NoteListFilter(),
    NoteListOrder order = const NoteListOrder(),
  }) {
    assert(
      projectId == null || !onlyNoProject,
      'projectId and onlyNoProject are mutually exclusive',
    );
    if (filter.tagIds.length > 20) {
      throw ArgumentError.value(
        filter.tagIds.length,
        'filter.tagIds',
        'at most 20 tags are supported',
      );
    }
    final periodStart = filter.periodStartUtc;
    final periodEnd = filter.periodEndUtcExclusive;
    if (periodStart != null && periodEnd != null && periodStart >= periodEnd) {
      throw ArgumentError('period start must be before its exclusive end');
    }
    final n = db.notes;
    final query = db.select(n).join([
      leftOuterJoin(db.projects, db.projects.id.equalsExp(n.projectId)),
    ])..where(n.deletedAtUtc.isNull());
    if (projectId != null) {
      query.where(n.projectId.equals(projectId));
    }
    if (onlyNoProject) {
      query.where(n.projectId.isNull());
    }
    if (onlyFavorites || filter.favoriteOnly) {
      query.where(n.isFavorite.equals(true));
    }

    if (filter.projectIds.isNotEmpty || filter.includeNoProject) {
      Expression<bool>? projectPredicate;
      if (filter.projectIds.isNotEmpty) {
        projectPredicate = n.projectId.isIn(filter.projectIds);
      }
      if (filter.includeNoProject) {
        final noProject = n.projectId.isNull();
        projectPredicate = projectPredicate == null
            ? noProject
            : projectPredicate | noProject;
      }
      query.where(projectPredicate!);
    }
    if (filter.statuses.isNotEmpty) {
      query.where(n.status.isInValues(filter.statuses));
    }
    if (filter.periodStartUtc case final start?) {
      query.where(n.createdAtUtc.isBiggerOrEqualValue(start));
    }
    if (filter.periodEndUtcExclusive case final end?) {
      query.where(n.createdAtUtc.isSmallerThanValue(end));
    }

    Expression<bool> readyAssetExists(AssetKind kind) {
      final assetQuery = db.selectOnly(db.mediaAssets)
        ..addColumns([db.mediaAssets.id])
        ..where(
          db.mediaAssets.ownerNoteId.equalsExp(n.id) &
              db.mediaAssets.kind.equalsValue(kind) &
              db.mediaAssets.lifecycleState.equalsValue(AssetLifecycle.ready) &
              db.mediaAssets.deletedAtUtc.isNull(),
        );
      return existsQuery(assetQuery);
    }

    if (filter.requireAudio) {
      query.where(readyAssetExists(AssetKind.audio));
    }
    if (filter.requireImage) {
      query.where(readyAssetExists(AssetKind.image));
    }
    if (filter.requireTranscript) {
      final transcriptQuery = db.selectOnly(db.transcriptRevisions)
        ..addColumns([db.transcriptRevisions.id])
        ..where(
          db.transcriptRevisions.noteId.equalsExp(n.id) &
              db.transcriptRevisions.state.equalsValue(TranscriptState.ready),
        );
      query.where(existsQuery(transcriptQuery));
    }

    if (filter.tagIds.isNotEmpty) {
      if (filter.tagMatchMode == TagMatchMode.any) {
        final tagQuery = db.selectOnly(db.noteTags)
          ..addColumns([db.noteTags.tagId])
          ..where(
            db.noteTags.noteId.equalsExp(n.id) &
                db.noteTags.tagId.isIn(filter.tagIds),
          );
        query.where(existsQuery(tagQuery));
      } else {
        for (final tagId in filter.tagIds) {
          final tagQuery = db.selectOnly(db.noteTags)
            ..addColumns([db.noteTags.tagId])
            ..where(
              db.noteTags.noteId.equalsExp(n.id) &
                  db.noteTags.tagId.equals(tagId),
            );
          query.where(existsQuery(tagQuery));
        }
      }
    }

    final sortExpression = switch (order.field) {
      NoteSortField.createdAt => n.createdAtUtc,
      NoteSortField.updatedAt => n.updatedAtUtc,
      NoteSortField.eventAt => ifNull(n.eventAtUtc, n.createdAtUtc),
      NoteSortField.title => _titleSortExpression,
      NoteSortField.project => db.projects.name.collate(Collate.noCase),
    };
    final mode = order.direction == NoteSortDirection.ascending
        ? OrderingMode.asc
        : OrderingMode.desc;
    query.orderBy([
      OrderingTerm(
        expression: sortExpression,
        mode: mode,
        nulls: NullsOrder.last,
      ),
      OrderingTerm(expression: n.id, mode: mode),
    ]);
    return query;
  }

  Expression<bool> _cursorPredicate(
    NoteListCursor cursor,
    NoteListOrder order,
  ) {
    final n = db.notes;
    final ascending = order.direction == NoteSortDirection.ascending;

    Expression<bool> compareInt(Expression<int> expression, int value) {
      final boundary = Variable<int>(value);
      final beyond = ascending
          ? expression.isBiggerThan(boundary)
          : expression.isSmallerThan(boundary);
      final tiedId = ascending
          ? n.id.isBiggerThanValue(cursor.id)
          : n.id.isSmallerThanValue(cursor.id);
      return beyond | (expression.equalsExp(boundary) & tiedId);
    }

    Expression<bool> compareText(Expression<String> expression, String value) {
      final boundary = Variable<String>(value);
      final beyond = ascending
          ? expression.isBiggerThan(boundary)
          : expression.isSmallerThan(boundary);
      final tiedId = ascending
          ? n.id.isBiggerThanValue(cursor.id)
          : n.id.isSmallerThanValue(cursor.id);
      return beyond | (expression.equalsExp(boundary) & tiedId);
    }

    return switch (order.field) {
      NoteSortField.createdAt => compareInt(
        n.createdAtUtc,
        _requireCursor<int>(cursor, order.field),
      ),
      NoteSortField.updatedAt => compareInt(
        n.updatedAtUtc,
        _requireCursor<int>(cursor, order.field),
      ),
      NoteSortField.eventAt => compareInt(
        ifNull(n.eventAtUtc, n.createdAtUtc),
        _requireCursor<int>(cursor, order.field),
      ),
      NoteSortField.title => compareText(
        _titleSortExpression,
        _requireCursor<String>(cursor, order.field),
      ),
      NoteSortField.project => _projectCursorPredicate(cursor, ascending),
    };
  }

  Expression<bool> _projectCursorPredicate(
    NoteListCursor cursor,
    bool ascending,
  ) {
    final n = db.notes;
    final projectName = db.projects.name.collate(Collate.noCase);
    final tiedId = ascending
        ? n.id.isBiggerThanValue(cursor.id)
        : n.id.isSmallerThanValue(cursor.id);
    final value = cursor.sortValue;
    if (value == null) {
      return db.projects.name.isNull() & tiedId;
    }
    if (value is! String) {
      throw ArgumentError('project cursor must contain a string or null');
    }
    final boundary = Variable<String>(value);
    final beyond = ascending
        ? projectName.isBiggerThan(boundary)
        : projectName.isSmallerThan(boundary);
    return beyond |
        (projectName.equalsExp(boundary) & tiedId) |
        db.projects.name.isNull();
  }

  T _requireCursor<T>(NoteListCursor cursor, NoteSortField field) {
    final value = cursor.sortValue;
    if (value is T) return value;
    throw ArgumentError('invalid cursor for ${field.name}');
  }

  Object? _cursorValue(Note note, Project? project, NoteSortField field) {
    return switch (field) {
      NoteSortField.createdAt => note.createdAtUtc,
      NoteSortField.updatedAt => note.updatedAtUtc,
      NoteSortField.eventAt => note.eventAtUtc ?? note.createdAtUtc,
      NoteSortField.title => note.title ?? _titleSortFallback(note.documentPlainText),
      NoteSortField.project => project?.name,
    };
  }

  /// Сортировка «Заголовок»: явный title, иначе усечённое начало текста —
  /// курсор не таскает весь plain text.
  static const _titleSortFallbackLength = 64;

  Expression<String> get _titleSortExpression => ifNull(
    db.notes.title,
    db.notes.documentPlainText.substr(1, _titleSortFallbackLength),
  ).collate(Collate.noCase);

  static String _titleSortFallback(String text) {
    if (text.length <= _titleSortFallbackLength) return text;
    var end = _titleSortFallbackLength;
    // Не разрезаем суррогатную пару на границе.
    if ((text.codeUnitAt(end) & 0xFC00) == 0xDC00) end--;
    return text.substring(0, end);
  }

  Stream<MediaAsset?> watchReadyAudioAsset(String noteId) {
    return watchAudioAssets(noteId).map(
      (assets) => assets.where((asset) {
        return asset.lifecycleState == AssetLifecycle.ready;
      }).firstOrNull,
    );
  }

  Stream<List<MediaAsset>> watchAudioAssets(String noteId) {
    final query = db.select(db.mediaAssets)
      ..where(
        (a) =>
            a.ownerNoteId.equals(noteId) &
            a.kind.equalsValue(AssetKind.audio) &
            a.lifecycleState.isInValues([
              AssetLifecycle.ready,
              AssetLifecycle.missing,
            ]) &
            a.deletedAtUtc.isNull(),
      )
      ..orderBy([
        (a) => OrderingTerm.asc(a.createdAtUtc),
        (a) => OrderingTerm.asc(a.id),
      ]);
    return query.watch();
  }

  Stream<List<TrashedAudioItem>> watchTrashedAudio() {
    final query =
        db.select(db.mediaAssets).join([
            innerJoin(
              db.notes,
              db.notes.id.equalsExp(db.mediaAssets.ownerNoteId),
            ),
          ])
          ..where(
            db.mediaAssets.kind.equalsValue(AssetKind.audio) &
                db.mediaAssets.deletedAtUtc.isNotNull() &
                db.mediaAssets.lifecycleState.isInValues([
                  AssetLifecycle.ready,
                  AssetLifecycle.missing,
                ]),
          )
          ..orderBy([
            OrderingTerm.desc(db.mediaAssets.deletedAtUtc),
            OrderingTerm.desc(db.mediaAssets.id),
          ]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => TrashedAudioItem(
              asset: row.readTable(db.mediaAssets),
              note: row.readTable(db.notes),
            ),
          )
          .toList(growable: false),
    );
  }

  Stream<List<TranscriptRevision>> watchRevisions(String noteId) {
    final query = db.select(db.transcriptRevisions)
      ..where((r) => r.noteId.equals(noteId))
      ..orderBy([(r) => OrderingTerm.desc(r.createdAtUtc)]);
    return query.watch();
  }

  /// FTS5-поиск по title + plain text (FR-SRC-001).
  Future<List<Note>> searchNotes(String query, {int limit = 50}) async {
    final match = _toFtsQuery(query);
    if (match.isEmpty) return const [];
    final pattern = '%${_escapeLike(query.trim())}%';
    final results = <String, Note>{};
    final textRows = await db.searchNotes(match, limit).get();
    for (final row in textRows) {
      results[row.n.id] = row.n;
    }
    final metadataRows = await db.searchNotesByMetadata(pattern, limit).get();
    for (final row in metadataRows) {
      results.putIfAbsent(row.n.id, () => row.n);
      if (results.length >= limit) break;
    }
    return results.values.take(limit).toList(growable: false);
  }

  /// Пользовательский ввод — не FTS-синтаксис: каждое слово экранируется
  /// кавычками и матчится по префиксу.
  static String _toFtsQuery(String raw) {
    final words = raw
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll('"', '').trim())
        .where((w) => w.isNotEmpty);
    return words.map((w) => '"$w"*').join(' ');
  }

  static String _escapeLike(String raw) =>
      raw.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  // ---------- Mutations ----------

  Future<String> createTextNote(
    String text, {
    String? projectId,
    SourceKind sourceKind = SourceKind.keyboard,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('note text must not be empty');
    }
    final document = PotokDocument.fromPlainText(trimmed);
    final id = ids.newId();
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: id,
              title: Value(titleGenerator.suggest(document.plainText)),
              projectId: Value(projectId),
              documentJson: document.encode(),
              documentPlainText: document.plainText,
              sourceKind: sourceKind,
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      await _appendEvent(
        id,
        NoteEventKind.created,
        projectId: projectId,
        at: now,
      );
      await _journal(
        entityId: id,
        operationKind: 'note.create',
        baseRevision: null,
        newRevision: 1,
        at: now,
      );
    });
    return id;
  }

  static const _imageDraftTitle = '__potok_image_draft__';

  /// Durable owner for managed images selected before quick capture is
  /// published. The same hidden-row protocol is used by audio staging.
  Future<Note> beginImageNoteDraft({
    String? projectId,
    SourceKind sourceKind = SourceKind.keyboard,
  }) async {
    final id = ids.newId();
    final now = clock.nowUtcMillis();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            title: const Value(_imageDraftTitle),
            projectId: Value(projectId),
            documentJson: const PotokDocument.empty().encode(),
            documentPlainText: '',
            sourceKind: sourceKind,
            isHidden: const Value(true),
            createdAtUtc: now,
            updatedAtUtc: now,
            deletedAtUtc: Value(now),
          ),
        );
    return (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle();
  }

  Future<Note?> findImageNoteDraft() {
    final query = db.select(db.notes)
      ..where(
        (n) =>
            n.isHidden.equals(true) &
            n.title.equals(_imageDraftTitle) &
            n.deletedAtUtc.isNotNull(),
      )
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAtUtc)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  Future<void> updateImageNoteDraft(
    Note draft,
    PotokDocument document, {
    String? projectId,
  }) async {
    final now = clock.nowUtcMillis();
    final updated =
        await (db.update(db.notes)..where(
              (n) =>
                  n.id.equals(draft.id) &
                  n.revision.equals(draft.revision) &
                  n.isHidden.equals(true),
            ))
            .write(
              NotesCompanion(
                projectId: Value(projectId),
                documentJson: Value(document.encode()),
                documentPlainText: Value(document.plainText),
                updatedAtUtc: Value(now),
                revision: Value(draft.revision + 1),
              ),
            );
    if (updated == 0) throw StateError('image draft was modified');
  }

  Future<void> publishImageNoteDraft(
    Note draft,
    PotokDocument document, {
    String? projectId,
  }) async {
    if (document.plainText.isEmpty && document.managedAssetIds.isEmpty) {
      throw ArgumentError('image draft must contain text or image');
    }
    final assetIds = document.managedAssetIds;
    if (assetIds.isNotEmpty) {
      final readyAssets =
          await (db.select(db.mediaAssets)..where(
                (asset) =>
                    asset.id.isIn(assetIds) &
                    asset.ownerNoteId.equals(draft.id) &
                    asset.kind.equalsValue(AssetKind.image) &
                    asset.lifecycleState.equalsValue(AssetLifecycle.ready) &
                    asset.deletedAtUtc.isNull(),
              ))
              .get();
      if (readyAssets.length != assetIds.length) {
        throw StateError('image draft contains unavailable assets');
      }
    }
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final updated =
          await (db.update(db.notes)..where(
                (n) =>
                    n.id.equals(draft.id) &
                    n.revision.equals(draft.revision) &
                    n.isHidden.equals(true),
              ))
              .write(
                NotesCompanion(
                  title: Value(
                    titleGenerator.suggest(document.plainText) ?? 'Изображение',
                  ),
                  projectId: Value(projectId),
                  documentJson: Value(document.encode()),
                  documentPlainText: Value(document.plainText),
                  isHidden: const Value(false),
                  deletedAtUtc: const Value(null),
                  updatedAtUtc: Value(now),
                  revision: Value(draft.revision + 1),
                ),
              );
      if (updated == 0) throw StateError('image draft was modified');
      await _appendEvent(
        draft.id,
        NoteEventKind.created,
        projectId: projectId,
        at: now,
      );
      await _journal(
        entityId: draft.id,
        operationKind: 'note.create',
        baseRevision: draft.revision,
        newRevision: draft.revision + 1,
        at: now,
      );
    });
  }

  Future<void> discardImageNoteDraft(Note draft) async {
    await (db.delete(db.notes)..where(
          (n) => n.id.equals(draft.id) & n.isHidden.equals(true),
        ))
        .go();
  }

  /// Регистрирует staged-запись и возвращает путь для рекордера. Строки в БД
  /// создаются в `staging` до появления байтов; заметка скрыта из списков
  /// до финализации.
  Future<StagedRecording> beginAudioNote({
    required String extension,
    String? projectId,
    SourceKind sourceKind = SourceKind.audio,
  }) async {
    final noteId = ids.newId();
    final assetId = ids.newId();
    final relativePath = media.relativePathFor(assetId, extension);
    await media.prepareStaging(relativePath);
    final now = clock.nowUtcMillis();
    try {
      await db.transaction(() async {
        await db
            .into(db.notes)
            .insert(
              NotesCompanion.insert(
                id: noteId,
                projectId: Value(projectId),
                documentJson: const PotokDocument.empty().encode(),
                documentPlainText: '',
                sourceKind: sourceKind,
                isHidden: const Value(true),
                createdAtUtc: now,
                updatedAtUtc: now,
                deletedAtUtc: Value(now),
              ),
            );
        await db
            .into(db.mediaAssets)
            .insert(
              MediaAssetsCompanion.insert(
                id: assetId,
                ownerNoteId: noteId,
                kind: AssetKind.audio,
                relativePath: relativePath,
                mimeType: extension == 'wav' ? 'audio/wav' : 'audio/mp4',
                lifecycleState: AssetLifecycle.staging,
                createdAtUtc: now,
                updatedAtUtc: now,
              ),
            );
      });
    } catch (_) {
      await media.discardStaging(relativePath);
      rethrow;
    }
    return StagedRecording(
      noteId: noteId,
      assetId: assetId,
      relativePath: relativePath,
      stagingPath: media.stagingPath(relativePath),
      createsNote: true,
    );
  }

  /// Adds another independent recording to an existing visible note.
  Future<StagedRecording> beginAudioAttachment(
    Note note, {
    String extension = 'm4a',
  }) async {
    final assetId = ids.newId();
    final relativePath = media.relativePathFor(assetId, extension);
    await media.prepareStaging(relativePath);
    final now = clock.nowUtcMillis();
    try {
      final current =
          await (db.select(db.notes)..where(
                (row) =>
                    row.id.equals(note.id) &
                    row.revision.equals(note.revision) &
                    row.deletedAtUtc.isNull(),
              ))
              .getSingleOrNull();
      if (current == null) throw StateError('note changed or unavailable');
      await db
          .into(db.mediaAssets)
          .insert(
            MediaAssetsCompanion.insert(
              id: assetId,
              ownerNoteId: note.id,
              kind: AssetKind.audio,
              relativePath: relativePath,
              mimeType: extension == 'wav' ? 'audio/wav' : 'audio/mp4',
              lifecycleState: AssetLifecycle.staging,
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
    } catch (_) {
      await media.discardStaging(relativePath);
      rethrow;
    }
    return StagedRecording(
      noteId: note.id,
      assetId: assetId,
      relativePath: relativePath,
      stagingPath: media.stagingPath(relativePath),
      createsNote: false,
      baseRevision: note.revision,
    );
  }

  /// Финализация: валидация + hash + atomic rename, затем короткий DB-commit
  /// делает asset `ready`, заметку видимой и пишет событие создания.
  Future<void> finishAudioNote(
    StagedRecording staged, {
    required Duration duration,
    required String codec,
    required int sampleRateHz,
    required int channels,
    String? comment,
  }) async {
    if (!staged.createsNote && (comment?.trim().isNotEmpty ?? false)) {
      throw ArgumentError('comments belong to the existing note document');
    }
    final now = clock.nowUtcMillis();
    final normalizedComment = comment?.trim() ?? '';
    final document = normalizedComment.isEmpty
        ? const PotokDocument.empty()
        : PotokDocument.fromPlainText(normalizedComment);
    // Recovery metadata is durable while the note is still hidden. A startup
    // repair can therefore finish either side of the atomic file rename.
    await db.transaction(() async {
      if (staged.createsNote) {
        await (db.update(
          db.notes,
        )..where((n) => n.id.equals(staged.noteId))).write(
          NotesCompanion(
            title: Value(titleGenerator.suggest(document.plainText)),
            documentJson: Value(document.encode()),
            documentPlainText: Value(document.plainText),
            updatedAtUtc: Value(now),
          ),
        );
      }
      await db
          .into(db.audioRecordings)
          .insert(
            AudioRecordingsCompanion.insert(
              assetId: staged.assetId,
              durationMs: duration.inMilliseconds,
              codec: codec,
              sampleRateHz: sampleRateHz,
              channels: channels,
              recordedAtUtc: now,
            ),
            mode: InsertMode.insertOrReplace,
          );
    });
    await _publishStagedAudio(staged);
  }

  /// Completes a recording left in `staging` by process death.
  Future<void> recoverStagedAudio(MediaAsset asset) async {
    if (asset.kind != AssetKind.audio ||
        asset.lifecycleState != AssetLifecycle.staging) {
      throw ArgumentError('asset is not a staged audio recording');
    }
    final metadata = await (db.select(
      db.audioRecordings,
    )..where((row) => row.assetId.equals(asset.id))).getSingleOrNull();
    if (metadata == null) {
      throw StateError('staged audio has no recovery metadata');
    }
    final note = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(asset.ownerNoteId))).getSingle();
    await _publishStagedAudio(
      StagedRecording(
        noteId: asset.ownerNoteId,
        assetId: asset.id,
        relativePath: asset.relativePath,
        stagingPath: media.stagingPath(asset.relativePath),
        createsNote: note.deletedAtUtc != null,
        baseRevision: note.deletedAtUtc == null ? note.revision : null,
      ),
    );
  }

  Future<void> _publishStagedAudio(StagedRecording staged) async {
    final published = await media.inspect(
      staged.relativePath,
      validateAudio: true,
    );
    final result = published ?? await media.finalizeAudio(staged.relativePath);
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final note = await (db.select(
        db.notes,
      )..where((row) => row.id.equals(staged.noteId))).getSingle();
      final asset = await (db.select(
        db.mediaAssets,
      )..where((row) => row.id.equals(staged.assetId))).getSingle();
      if (asset.lifecycleState == AssetLifecycle.ready) return;
      if (asset.lifecycleState != AssetLifecycle.staging) {
        throw StateError('audio asset is not staging');
      }
      await (db.update(
        db.mediaAssets,
      )..where((a) => a.id.equals(staged.assetId))).write(
        MediaAssetsCompanion(
          lifecycleState: const Value(AssetLifecycle.ready),
          sizeBytes: Value(result.sizeBytes),
          sha256: Value(result.sha256hex),
          updatedAtUtc: Value(now),
        ),
      );
      if (staged.createsNote) {
        await (db.update(
          db.notes,
        )..where((n) => n.id.equals(staged.noteId))).write(
          NotesCompanion(
            isHidden: const Value(false),
            deletedAtUtc: const Value(null),
            updatedAtUtc: Value(now),
          ),
        );
        await _appendEvent(
          staged.noteId,
          NoteEventKind.created,
          projectId: note.projectId,
          at: now,
        );
        await _journal(
          entityId: staged.noteId,
          operationKind: 'note.create_audio',
          baseRevision: null,
          newRevision: 1,
          at: now,
        );
      } else {
        final baseRevision = staged.baseRevision;
        if (baseRevision == null) {
          throw StateError('audio attachment has no base revision');
        }
        final changed =
            await (db.update(db.notes)..where(
                  (row) =>
                      row.id.equals(staged.noteId) &
                      row.revision.equals(baseRevision) &
                      row.deletedAtUtc.isNull(),
                ))
                .write(
                  NotesCompanion(
                    updatedAtUtc: Value(now),
                    revision: Value(baseRevision + 1),
                  ),
                );
        if (changed == 0) throw StateError('note changed during recording');
        await _appendEvent(
          staged.noteId,
          NoteEventKind.edited,
          projectId: note.projectId,
          at: now,
        );
        await _journal(
          entityId: staged.noteId,
          operationKind: 'note.attach_audio',
          baseRevision: baseRevision,
          newRevision: baseRevision + 1,
          at: now,
        );
      }
    });
  }

  Future<void> moveAudioToTrash(Note note, MediaAsset asset) async {
    if (asset.ownerNoteId != note.id || asset.kind != AssetKind.audio) {
      throw ArgumentError('audio does not belong to note');
    }
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final changed =
          await (db.update(db.mediaAssets)..where(
                (row) => row.id.equals(asset.id) & row.deletedAtUtc.isNull(),
              ))
              .write(
                MediaAssetsCompanion(
                  deletedAtUtc: Value(now),
                  updatedAtUtc: Value(now),
                ),
              );
      if (changed == 0) throw StateError('audio already removed');
      final noteChanged =
          await (db.update(db.notes)..where(
                (row) =>
                    row.id.equals(note.id) & row.revision.equals(note.revision),
              ))
              .write(
                NotesCompanion(
                  updatedAtUtc: Value(now),
                  revision: Value(note.revision + 1),
                ),
              );
      if (noteChanged == 0) throw StateError('note changed concurrently');
      await _appendEvent(
        note.id,
        NoteEventKind.edited,
        projectId: note.projectId,
        at: now,
      );
      await _journal(
        entityId: note.id,
        operationKind: 'note.trash_audio',
        baseRevision: note.revision,
        newRevision: note.revision + 1,
        at: now,
      );
    });
  }

  Future<void> restoreAudio(Note note, MediaAsset asset) async {
    if (asset.kind != AssetKind.audio ||
        asset.deletedAtUtc == null ||
        asset.ownerNoteId != note.id) {
      throw ArgumentError('audio is not in trash');
    }
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final restored =
          await (db.update(db.mediaAssets)..where(
                (row) => row.id.equals(asset.id) & row.deletedAtUtc.isNotNull(),
              ))
              .write(
                MediaAssetsCompanion(
                  deletedAtUtc: const Value(null),
                  updatedAtUtc: Value(now),
                ),
              );
      if (restored == 0) throw StateError('audio already restored');
      await _touchNoteForAudioLifecycle(
        note,
        at: now,
        operationKind: 'note.restore_audio',
      );
    });
  }

  Future<void> purgeAudio(Note note, MediaAsset asset) async {
    if (asset.kind != AssetKind.audio ||
        asset.deletedAtUtc == null ||
        asset.ownerNoteId != note.id) {
      throw ArgumentError('only trashed audio can be purged');
    }
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      await (db.delete(
        db.transcriptRevisions,
      )..where((row) => row.audioAssetId.equals(asset.id))).go();
      await (db.delete(
        db.audioRecordings,
      )..where((row) => row.assetId.equals(asset.id))).go();
      final tombstoned =
          await (db.update(db.mediaAssets)..where(
                (row) => row.id.equals(asset.id) & row.deletedAtUtc.isNotNull(),
              ))
              .write(
                MediaAssetsCompanion(
                  lifecycleState: const Value(AssetLifecycle.deleted),
                  sizeBytes: const Value(0),
                  updatedAtUtc: Value(now),
                ),
              );
      if (tombstoned == 0) throw StateError('audio already purged');
      await _touchNoteForAudioLifecycle(
        note,
        at: now,
        operationKind: 'note.purge_audio',
      );
    });
    await media.discard(asset.relativePath);
  }

  Future<void> _touchNoteForAudioLifecycle(
    Note note, {
    required int at,
    required String operationKind,
  }) async {
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
    await _appendEvent(
      note.id,
      NoteEventKind.edited,
      projectId: note.projectId,
      at: at,
    );
    await _journal(
      entityId: note.id,
      operationKind: operationKind,
      baseRevision: note.revision,
      newRevision: note.revision + 1,
      at: at,
    );
  }

  /// Отменённая/сорвавшаяся запись: staged-байты и скрытые строки удаляются,
  /// видимого состояния не существовало.
  Future<void> abortAudioNote(StagedRecording staged) async {
    await media.discard(staged.relativePath);
    await db.transaction(() async {
      await (db.delete(
        db.audioRecordings,
      )..where((row) => row.assetId.equals(staged.assetId))).go();
      await (db.delete(
        db.mediaAssets,
      )..where((a) => a.id.equals(staged.assetId))).go();
      if (staged.createsNote) {
        await (db.delete(
          db.notes,
        )..where((n) => n.id.equals(staged.noteId))).go();
      }
    });
  }

  /// Явное принятие: расшифровка добавляется параграфом, существующий текст
  /// не заменяется (FR-ASR-004). Optimistic concurrency через revision guard.
  Future<void> acceptTranscript(String noteId, String revisionId) async {
    await db.transaction(() async {
      final note = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(noteId))).getSingle();
      final revision = await (db.select(
        db.transcriptRevisions,
      )..where((r) => r.id.equals(revisionId))).getSingle();
      if (revision.state != TranscriptState.ready) {
        throw StateError('transcript is not ready');
      }
      final document = PotokDocument.decode(
        note.documentJson,
      ).appendParagraph(revision.rawText);
      final now = clock.nowUtcMillis();
      final updated =
          await (db.update(db.notes)..where(
                (n) => n.id.equals(noteId) & n.revision.equals(note.revision),
              ))
              .write(
                NotesCompanion(
                  title:
                      note.title == null ||
                          note.title!.trim().isEmpty ||
                          note.title ==
                              titleGenerator.suggest(note.documentPlainText)
                      ? Value(titleGenerator.suggest(document.plainText))
                      : const Value.absent(),
                  documentJson: Value(document.encode()),
                  documentPlainText: Value(document.plainText),
                  updatedAtUtc: Value(now),
                  revision: Value(note.revision + 1),
                ),
              );
      if (updated == 0) {
        throw StateError('note was modified concurrently, retry');
      }
      await (db.update(db.transcriptRevisions)
            ..where((r) => r.id.equals(revisionId)))
          .write(TranscriptRevisionsCompanion(acceptedAtUtc: Value(now)));
      await _appendEvent(
        noteId,
        NoteEventKind.edited,
        projectId: note.projectId,
        at: now,
      );
      await _journal(
        entityId: noteId,
        operationKind: 'note.accept_transcript',
        baseRevision: note.revision,
        newRevision: note.revision + 1,
        at: now,
      );
    });
  }

  /// Explicit user title. Empty means "return to automatic title".
  Future<void> updateTitle(Note note, String value) async {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length > 120) {
      throw ArgumentError.value(value, 'value', 'title is too long');
    }
    final next = normalized.isEmpty
        ? titleGenerator.suggest(note.documentPlainText)
        : normalized;
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final changed =
          await (db.update(db.notes)..where(
                (row) =>
                    row.id.equals(note.id) & row.revision.equals(note.revision),
              ))
              .write(
                NotesCompanion(
                  title: Value(next),
                  updatedAtUtc: Value(now),
                  revision: Value(note.revision + 1),
                ),
              );
      if (changed == 0) throw StateError('note changed concurrently');
      await _appendEvent(
        note.id,
        NoteEventKind.edited,
        projectId: note.projectId,
        at: now,
      );
      await _journal(
        entityId: note.id,
        operationKind: 'note.update_title',
        baseRevision: note.revision,
        newRevision: note.revision + 1,
        at: now,
      );
    });
  }

  /// ASR may suggest a title without accepting transcript into the document.
  /// A non-empty existing title is never overwritten.
  Future<void> suggestTitleFromTranscript(String noteId, String text) async {
    final suggestion = titleGenerator.suggest(text);
    if (suggestion == null) return;
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final note = await (db.select(
        db.notes,
      )..where((row) => row.id.equals(noteId))).getSingleOrNull();
      if (note == null || (note.title?.trim().isNotEmpty ?? false)) return;
      final changed =
          await (db.update(db.notes)..where(
                (row) =>
                    row.id.equals(noteId) & row.revision.equals(note.revision),
              ))
              .write(
                NotesCompanion(
                  title: Value(suggestion),
                  updatedAtUtc: Value(now),
                  revision: Value(note.revision + 1),
                ),
              );
      if (changed == 0) return;
      await _appendEvent(
        noteId,
        NoteEventKind.edited,
        projectId: note.projectId,
        at: now,
      );
      await _journal(
        entityId: noteId,
        operationKind: 'note.suggest_title',
        baseRevision: note.revision,
        newRevision: note.revision + 1,
        at: now,
      );
    });
  }

  Future<void> toggleDone(Note note) async {
    final now = clock.nowUtcMillis();
    final next = note.status == NoteStatus.done
        ? NoteStatus.inWork
        : NoteStatus.done;
    await db.transaction(() async {
      final updated =
          await (db.update(db.notes)..where(
                (n) => n.id.equals(note.id) & n.revision.equals(note.revision),
              ))
              .write(
                NotesCompanion(
                  status: Value(next),
                  completedAtUtc: Value(next == NoteStatus.done ? now : null),
                  updatedAtUtc: Value(now),
                  revision: Value(note.revision + 1),
                ),
              );
      if (updated == 0) {
        throw StateError('note was modified concurrently, retry');
      }
      await _appendEvent(
        note.id,
        next == NoteStatus.done
            ? NoteEventKind.completed
            : NoteEventKind.reopened,
        projectId: note.projectId,
        at: now,
      );
      await _journal(
        entityId: note.id,
        operationKind: next == NoteStatus.done
            ? 'note.complete'
            : 'note.reopen',
        baseRevision: note.revision,
        newRevision: note.revision + 1,
        at: now,
      );
    });
  }

  /// Обновление документа (редактор/автосохранение): revision guard,
  /// событие edited и журнал в одной транзакции.
  Future<void> updateDocument(Note note, PotokDocument document) async {
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final updated =
          await (db.update(db.notes)..where(
                (n) => n.id.equals(note.id) & n.revision.equals(note.revision),
              ))
              .write(
                NotesCompanion(
                  title:
                      note.title == null ||
                          note.title!.trim().isEmpty ||
                          note.title ==
                              titleGenerator.suggest(note.documentPlainText)
                      ? Value(titleGenerator.suggest(document.plainText))
                      : const Value.absent(),
                  documentJson: Value(document.encode()),
                  documentPlainText: Value(document.plainText),
                  updatedAtUtc: Value(now),
                  revision: Value(note.revision + 1),
                ),
              );
      if (updated == 0) {
        throw StateError('note was modified concurrently, retry');
      }
      await _appendEvent(
        note.id,
        NoteEventKind.edited,
        projectId: note.projectId,
        at: now,
      );
      await _journal(
        entityId: note.id,
        operationKind: 'note.update',
        baseRevision: note.revision,
        newRevision: note.revision + 1,
        at: now,
      );
    });
  }

  /// Перенос в проект (FR-MOV-005): смена project, разрешение конфликтов
  /// project-тегов и history event — атомарно.
  Future<void> moveToProject(
    Note note,
    String? targetProjectId, {
    ProjectTagResolution resolution = ProjectTagResolution.drop,
  }) async {
    if (note.projectId == targetProjectId) return;
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final updated =
          await (db.update(db.notes)..where(
                (n) => n.id.equals(note.id) & n.revision.equals(note.revision),
              ))
              .write(
                NotesCompanion(
                  projectId: Value(targetProjectId),
                  updatedAtUtc: Value(now),
                  revision: Value(note.revision + 1),
                ),
              );
      if (updated == 0) {
        throw StateError('note was modified concurrently, retry');
      }
      // Project-теги прежнего проекта конфликтуют с новым размещением.
      final rows = await (db.select(db.tags).join([
        innerJoin(db.noteTags, db.noteTags.tagId.equalsExp(db.tags.id)),
      ])..where(db.noteTags.noteId.equals(note.id))).get();
      for (final row in rows) {
        final tag = row.readTable(db.tags);
        final conflicting =
            tag.scope == TagScope.project && tag.projectId != targetProjectId;
        if (!conflicting) continue;
        switch (resolution) {
          case ProjectTagResolution.drop:
            await (db.delete(db.noteTags)..where(
                  (nt) => nt.noteId.equals(note.id) & nt.tagId.equals(tag.id),
                ))
                .go();
          case ProjectTagResolution.convertToGlobal:
            // Может нарушить уникальность имён global — исключение наружу,
            // UI показывает конфликт (массовое решение должно быть явным).
            await (db.update(db.tags)..where((t) => t.id.equals(tag.id))).write(
              TagsCompanion(
                scope: const Value(TagScope.global),
                projectId: const Value(null),
                updatedAtUtc: Value(now),
                revision: Value(tag.revision + 1),
              ),
            );
        }
      }
      await _appendEvent(
        note.id,
        NoteEventKind.movedToProject,
        projectId: note.projectId,
        at: now,
      );
      await _journal(
        entityId: note.id,
        operationKind: 'note.move',
        baseRevision: note.revision,
        newRevision: note.revision + 1,
        at: now,
      );
    });
  }

  /// Atomic bulk mutation for the bounded UI selection. Larger maintenance
  /// jobs must use an explicit chunk/progress protocol instead of hiding a
  /// partial result.
  Future<void> bulkSetStatus(
    Iterable<Note> selection,
    NoteStatus status,
  ) async {
    final notes = _validateBulkSelection(selection);
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      for (final note in notes) {
        final changed =
            await (db.update(db.notes)..where(
                  (row) =>
                      row.id.equals(note.id) &
                      row.revision.equals(note.revision) &
                      row.deletedAtUtc.isNull(),
                ))
                .write(
                  NotesCompanion(
                    status: Value(status),
                    completedAtUtc: Value(
                      status == NoteStatus.done ? now : null,
                    ),
                    updatedAtUtc: Value(now),
                    revision: Value(note.revision + 1),
                  ),
                );
        if (changed == 0) throw StateError('bulk status conflict');
        await _appendEvent(
          note.id,
          status == NoteStatus.done
              ? NoteEventKind.completed
              : NoteEventKind.reopened,
          projectId: note.projectId,
          at: now,
        );
        await _journal(
          entityId: note.id,
          operationKind: 'note.bulk_status',
          baseRevision: note.revision,
          newRevision: note.revision + 1,
          at: now,
        );
      }
    });
  }

  Future<void> bulkMoveToProject(
    Iterable<Note> selection,
    String? targetProjectId, {
    ProjectTagResolution resolution = ProjectTagResolution.drop,
  }) async {
    final notes = _validateBulkSelection(selection);
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      if (targetProjectId != null) {
        final target =
            await (db.select(db.projects)..where(
                  (row) =>
                      row.id.equals(targetProjectId) &
                      row.deletedAtUtc.isNull(),
                ))
                .getSingleOrNull();
        if (target == null) throw StateError('target project unavailable');
      }
      for (final note in notes) {
        if (note.projectId == targetProjectId) continue;
        final changed =
            await (db.update(db.notes)..where(
                  (row) =>
                      row.id.equals(note.id) &
                      row.revision.equals(note.revision) &
                      row.deletedAtUtc.isNull(),
                ))
                .write(
                  NotesCompanion(
                    projectId: Value(targetProjectId),
                    updatedAtUtc: Value(now),
                    revision: Value(note.revision + 1),
                  ),
                );
        if (changed == 0) throw StateError('bulk move conflict');
        final tagRows = await (db.select(db.tags).join([
          innerJoin(db.noteTags, db.noteTags.tagId.equalsExp(db.tags.id)),
        ])..where(db.noteTags.noteId.equals(note.id))).get();
        for (final row in tagRows) {
          final tag = row.readTable(db.tags);
          if (tag.scope != TagScope.project ||
              tag.projectId == targetProjectId) {
            continue;
          }
          switch (resolution) {
            case ProjectTagResolution.drop:
              await (db.delete(db.noteTags)..where(
                    (link) =>
                        link.noteId.equals(note.id) & link.tagId.equals(tag.id),
                  ))
                  .go();
            case ProjectTagResolution.convertToGlobal:
              await (db.update(
                db.tags,
              )..where((row) => row.id.equals(tag.id))).write(
                TagsCompanion(
                  scope: const Value(TagScope.global),
                  projectId: const Value(null),
                  updatedAtUtc: Value(now),
                  revision: Value(tag.revision + 1),
                ),
              );
          }
        }
        await _appendEvent(
          note.id,
          NoteEventKind.movedToProject,
          projectId: note.projectId,
          at: now,
        );
        await _journal(
          entityId: note.id,
          operationKind: 'note.bulk_move',
          baseRevision: note.revision,
          newRevision: note.revision + 1,
          at: now,
        );
      }
    });
  }

  Future<void> bulkMoveToTrash(Iterable<Note> selection) async {
    final notes = _validateBulkSelection(selection);
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      for (final note in notes) {
        final changed =
            await (db.update(db.notes)..where(
                  (row) =>
                      row.id.equals(note.id) &
                      row.revision.equals(note.revision) &
                      row.deletedAtUtc.isNull(),
                ))
                .write(
                  NotesCompanion(
                    deletedAtUtc: Value(now),
                    updatedAtUtc: Value(now),
                    revision: Value(note.revision + 1),
                  ),
                );
        if (changed == 0) throw StateError('bulk delete conflict');
        await _appendEvent(
          note.id,
          NoteEventKind.deleted,
          projectId: note.projectId,
          at: now,
        );
        await _journal(
          entityId: note.id,
          operationKind: 'note.bulk_trash',
          baseRevision: note.revision,
          newRevision: note.revision + 1,
          at: now,
        );
      }
    });
  }

  List<Note> _validateBulkSelection(Iterable<Note> selection) {
    final byId = <String, Note>{for (final note in selection) note.id: note};
    if (byId.isEmpty || byId.length > 500) {
      throw ArgumentError('bulk selection must contain 1..500 unique notes');
    }
    return byId.values.toList(growable: false);
  }

  Future<void> setFavorite(Note note, bool favorite) async {
    final now = clock.nowUtcMillis();
    final updated =
        await (db.update(db.notes)..where(
              (n) => n.id.equals(note.id) & n.revision.equals(note.revision),
            ))
            .write(
              NotesCompanion(
                isFavorite: Value(favorite),
                favoritedAtUtc: Value(favorite ? now : null),
                updatedAtUtc: Value(now),
                revision: Value(note.revision + 1),
              ),
            );
    if (updated == 0) {
      throw StateError('note was modified concurrently, retry');
    }
  }

  /// Корзина (FR-DEL-001): soft delete + событие deleted.
  Future<void> moveToTrash(Note note) => _setDeleted(note, deleted: true);

  Future<void> restoreFromTrash(Note note) => _setDeleted(note, deleted: false);

  Future<void> _setDeleted(Note note, {required bool deleted}) async {
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final updated =
          await (db.update(db.notes)..where(
                (n) => n.id.equals(note.id) & n.revision.equals(note.revision),
              ))
              .write(
                NotesCompanion(
                  deletedAtUtc: Value(deleted ? now : null),
                  updatedAtUtc: Value(now),
                  revision: Value(note.revision + 1),
                ),
              );
      if (updated == 0) {
        throw StateError('note was modified concurrently, retry');
      }
      await _appendEvent(
        note.id,
        deleted ? NoteEventKind.deleted : NoteEventKind.restored,
        projectId: note.projectId,
        at: now,
      );
      await _journal(
        entityId: note.id,
        operationKind: deleted ? 'note.trash' : 'note.restore',
        baseRevision: note.revision,
        newRevision: note.revision + 1,
        at: now,
      );
    });
  }

  Stream<List<Note>> watchTrash() {
    final query = db.select(db.notes)
      ..where((n) => n.deletedAtUtc.isNotNull() & n.isHidden.equals(false))
      ..orderBy([(n) => OrderingTerm.desc(n.deletedAtUtc)]);
    return query.watch();
  }

  Future<NoteListPage> fetchTrashPage({
    NoteListCursor? after,
    int pageSize = 50,
  }) async {
    if (pageSize < 1 || pageSize > 200) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be from 1 to 200');
    }
    final n = db.notes;
    final query = db.select(n)
      ..where(
        (row) => row.deletedAtUtc.isNotNull() & row.isHidden.equals(false),
      );
    if (after != null) {
      final deletedAt = _requireCursor<int>(after, NoteSortField.updatedAt);
      query.where(
        (row) =>
            row.deletedAtUtc.isSmallerThanValue(deletedAt) |
            (row.deletedAtUtc.equals(deletedAt) &
                row.id.isSmallerThanValue(after.id)),
      );
    }
    query
      ..orderBy([
        (row) => OrderingTerm.desc(row.deletedAtUtc),
        (row) => OrderingTerm.desc(row.id),
      ])
      ..limit(pageSize + 1);
    final rows = await query.get();
    final hasMore = rows.length > pageSize;
    final notes = List<Note>.unmodifiable(hasMore ? rows.take(pageSize) : rows);
    final last = notes.lastOrNull;
    return NoteListPage(
      notes: notes,
      nextCursor: hasMore && last != null
          ? NoteListCursor(sortValue: last.deletedAtUtc!, id: last.id)
          : null,
      hasMore: hasMore,
    );
  }

  // ---------- Internals (только внутри открытой транзакции) ----------

  Future<void> _appendEvent(
    String noteId,
    NoteEventKind kind, {
    required String? projectId,
    required int at,
  }) {
    return db
        .into(db.noteEvents)
        .insert(
          NoteEventsCompanion.insert(
            id: ids.newId(),
            noteId: noteId,
            projectIdAtEvent: Value(projectId),
            kind: kind,
            occurredAtUtc: at,
            deviceId: deviceId,
          ),
        );
  }

  Future<void> _journal({
    required String entityId,
    required String operationKind,
    required int? baseRevision,
    required int? newRevision,
    required int at,
  }) {
    return db
        .into(db.operationJournal)
        .insert(
          OperationJournalCompanion.insert(
            operationId: ids.newId(),
            deviceId: deviceId,
            entityKind: 'note',
            entityId: entityId,
            baseRevision: Value(baseRevision),
            newRevision: Value(newRevision),
            operationKind: operationKind,
            occurredAtUtc: at,
          ),
        );
  }
}

class StagedRecording {
  final String noteId;
  final String assetId;
  final String relativePath;
  final String stagingPath;
  final bool createsNote;
  final int? baseRevision;

  const StagedRecording({
    required this.noteId,
    required this.assetId,
    required this.relativePath,
    required this.stagingPath,
    this.createsNote = true,
    this.baseRevision,
  });
}

class TrashedAudioItem {
  final MediaAsset asset;
  final Note note;

  const TrashedAudioItem({required this.asset, required this.note});
}
