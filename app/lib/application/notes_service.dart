import 'package:drift/drift.dart';

import '../domain/clock.dart';
import '../domain/document.dart';
import '../domain/id_generator.dart';
import '../domain/types.dart';
import '../infrastructure/asr/local_speech_recognizer.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/media_store.dart';

/// Use cases заметок. Каждая мутация — одна транзакция: изменение сущности,
/// NoteEvent и OperationJournal фиксируются вместе или не фиксируются вовсе
/// (ТЗ 0.5.4, 0.9).
class NotesService {
  final AppDatabase db;
  final MediaStore media;
  final LocalSpeechRecognizer recognizer;
  final Clock clock;
  final IdGenerator ids;
  final String deviceId;

  NotesService({
    required this.db,
    required this.media,
    required this.recognizer,
    required this.clock,
    required this.ids,
    required this.deviceId,
  });

  // ---------- Queries ----------

  Stream<List<Note>> watchNotes() {
    final query = db.select(db.notes)
      ..where((n) => n.deletedAtUtc.isNull())
      ..orderBy([
        (n) => OrderingTerm.desc(n.createdAtUtc),
        (n) => OrderingTerm.desc(n.id), // stable tie-breaker (FR-LST-001)
      ]);
    return query.watch();
  }

  Stream<MediaAsset?> watchReadyAudioAsset(String noteId) {
    final query = db.select(db.mediaAssets)
      ..where((a) =>
          a.ownerNoteId.equals(noteId) &
          a.kind.equalsValue(AssetKind.audio) &
          a.lifecycleState.equalsValue(AssetLifecycle.ready) &
          a.deletedAtUtc.isNull())
      ..limit(1);
    return query.watchSingleOrNull();
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
    final rows = await db.searchNotes(match, limit).get();
    return rows.map((row) => row.n).toList(growable: false);
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

  // ---------- Mutations ----------

  Future<String> createTextNote(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('note text must not be empty');
    }
    final document = PotokDocument.fromPlainText(trimmed);
    final id = ids.newId();
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      await db.into(db.notes).insert(
            NotesCompanion.insert(
              id: id,
              documentJson: document.encode(),
              documentPlainText: document.plainText,
              sourceKind: SourceKind.keyboard,
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      await _appendEvent(id, NoteEventKind.created, projectId: null, at: now);
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

  /// Регистрирует staged-запись и возвращает путь для рекордера. Строки в БД
  /// создаются в `staging` до появления байтов; заметка скрыта из списков
  /// до финализации.
  Future<StagedRecording> beginAudioNote({required String extension}) async {
    final noteId = ids.newId();
    final assetId = ids.newId();
    final relativePath = media.relativePathFor(assetId, extension);
    await media.prepareStaging(relativePath);
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      await db.into(db.notes).insert(
            NotesCompanion.insert(
              id: noteId,
              documentJson: const PotokDocument.empty().encode(),
              documentPlainText: '',
              sourceKind: SourceKind.audio,
              createdAtUtc: now,
              updatedAtUtc: now,
              deletedAtUtc: Value(now),
            ),
          );
      await db.into(db.mediaAssets).insert(
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
    return StagedRecording(
      noteId: noteId,
      assetId: assetId,
      relativePath: relativePath,
      stagingPath: media.stagingPath(relativePath),
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
  }) async {
    final result = await media.finalize(staged.relativePath);
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      await (db.update(db.mediaAssets)
            ..where((a) => a.id.equals(staged.assetId)))
          .write(MediaAssetsCompanion(
        lifecycleState: const Value(AssetLifecycle.ready),
        sizeBytes: Value(result.sizeBytes),
        sha256: Value(result.sha256hex),
        updatedAtUtc: Value(now),
      ));
      await db.into(db.audioRecordings).insert(
            AudioRecordingsCompanion.insert(
              assetId: staged.assetId,
              durationMs: duration.inMilliseconds,
              codec: codec,
              sampleRateHz: sampleRateHz,
              channels: channels,
              recordedAtUtc: now,
            ),
          );
      await (db.update(db.notes)..where((n) => n.id.equals(staged.noteId)))
          .write(NotesCompanion(
        deletedAtUtc: const Value(null),
        updatedAtUtc: Value(now),
      ));
      await _appendEvent(staged.noteId, NoteEventKind.created,
          projectId: null, at: now);
      await _journal(
        entityId: staged.noteId,
        operationKind: 'note.create_audio',
        baseRevision: null,
        newRevision: 1,
        at: now,
      );
    });
  }

  /// Отменённая/сорвавшаяся запись: staged-байты и скрытые строки удаляются,
  /// видимого состояния не существовало.
  Future<void> abortAudioNote(StagedRecording staged) async {
    await media.discardStaging(staged.relativePath);
    await db.transaction(() async {
      await (db.delete(db.mediaAssets)
            ..where((a) => a.id.equals(staged.assetId)))
          .go();
      await (db.delete(db.notes)..where((n) => n.id.equals(staged.noteId)))
          .go();
    });
  }

  /// Каждая попытка ASR — новая TranscriptRevision; текст пользователя здесь
  /// не изменяется (FR-ASR-003/004).
  Future<TranscriptRevision> transcribe(
    String noteId,
    String assetId, {
    String languageHint = '',
  }) async {
    final asset = await (db.select(db.mediaAssets)
          ..where((a) => a.id.equals(assetId)))
        .getSingle();
    final revisionId = ids.newId();
    await db.into(db.transcriptRevisions).insert(
          TranscriptRevisionsCompanion.insert(
            id: revisionId,
            noteId: noteId,
            audioAssetId: assetId,
            engineId: recognizer.engineId,
            modelId: '',
            language: languageHint,
            state: TranscriptState.recognizing,
            createdAtUtc: clock.nowUtcMillis(),
          ),
        );
    try {
      final result = await recognizer.transcribeFile(
        media.absolutePath(asset.relativePath),
        languageHint: languageHint,
      );
      await (db.update(db.transcriptRevisions)
            ..where((r) => r.id.equals(revisionId)))
          .write(TranscriptRevisionsCompanion(
        rawText: Value(result.text),
        modelId: Value(result.modelId),
        language: Value(result.language),
        state: const Value(TranscriptState.ready),
      ));
    } on ModelUnavailableException {
      await _markRevision(revisionId, TranscriptState.waitingForModel, null);
      rethrow;
    } catch (e) {
      await _markRevision(revisionId, TranscriptState.failed, e.toString());
      rethrow;
    }
    return (db.select(db.transcriptRevisions)
          ..where((r) => r.id.equals(revisionId)))
        .getSingle();
  }

  /// Явное принятие: расшифровка добавляется параграфом, существующий текст
  /// не заменяется (FR-ASR-004). Optimistic concurrency через revision guard.
  Future<void> acceptTranscript(String noteId, String revisionId) async {
    await db.transaction(() async {
      final note = await (db.select(db.notes)
            ..where((n) => n.id.equals(noteId)))
          .getSingle();
      final revision = await (db.select(db.transcriptRevisions)
            ..where((r) => r.id.equals(revisionId)))
          .getSingle();
      if (revision.state != TranscriptState.ready) {
        throw StateError('transcript is not ready');
      }
      final document = PotokDocument.decode(note.documentJson)
          .appendParagraph(revision.rawText);
      final now = clock.nowUtcMillis();
      final updated = await (db.update(db.notes)
            ..where(
                (n) => n.id.equals(noteId) & n.revision.equals(note.revision)))
          .write(NotesCompanion(
        documentJson: Value(document.encode()),
        documentPlainText: Value(document.plainText),
        updatedAtUtc: Value(now),
        revision: Value(note.revision + 1),
      ));
      if (updated == 0) {
        throw StateError('note was modified concurrently, retry');
      }
      await (db.update(db.transcriptRevisions)
            ..where((r) => r.id.equals(revisionId)))
          .write(TranscriptRevisionsCompanion(acceptedAtUtc: Value(now)));
      await _appendEvent(noteId, NoteEventKind.edited,
          projectId: note.projectId, at: now);
      await _journal(
        entityId: noteId,
        operationKind: 'note.accept_transcript',
        baseRevision: note.revision,
        newRevision: note.revision + 1,
        at: now,
      );
    });
  }

  Future<void> toggleDone(Note note) async {
    final now = clock.nowUtcMillis();
    final next =
        note.status == NoteStatus.done ? NoteStatus.inWork : NoteStatus.done;
    await db.transaction(() async {
      final updated = await (db.update(db.notes)
            ..where((n) =>
                n.id.equals(note.id) & n.revision.equals(note.revision)))
          .write(NotesCompanion(
        status: Value(next),
        completedAtUtc: Value(next == NoteStatus.done ? now : null),
        updatedAtUtc: Value(now),
        revision: Value(note.revision + 1),
      ));
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
        operationKind:
            next == NoteStatus.done ? 'note.complete' : 'note.reopen',
        baseRevision: note.revision,
        newRevision: note.revision + 1,
        at: now,
      );
    });
  }

  // ---------- Internals (только внутри открытой транзакции) ----------

  Future<void> _appendEvent(
    String noteId,
    NoteEventKind kind, {
    required String? projectId,
    required int at,
  }) {
    return db.into(db.noteEvents).insert(NoteEventsCompanion.insert(
          id: ids.newId(),
          noteId: noteId,
          projectIdAtEvent: Value(projectId),
          kind: kind,
          occurredAtUtc: at,
          deviceId: deviceId,
        ));
  }

  Future<void> _journal({
    required String entityId,
    required String operationKind,
    required int? baseRevision,
    required int? newRevision,
    required int at,
  }) {
    return db.into(db.operationJournal).insert(OperationJournalCompanion.insert(
          operationId: ids.newId(),
          deviceId: deviceId,
          entityKind: 'note',
          entityId: entityId,
          baseRevision: Value(baseRevision),
          newRevision: Value(newRevision),
          operationKind: operationKind,
          occurredAtUtc: at,
        ));
  }

  Future<void> _markRevision(
    String id,
    TranscriptState state,
    String? error,
  ) async {
    await (db.update(db.transcriptRevisions)..where((r) => r.id.equals(id)))
        .write(TranscriptRevisionsCompanion(
      state: Value(state),
      errorMessage: Value(error),
    ));
  }
}

class StagedRecording {
  final String noteId;
  final String assetId;
  final String relativePath;
  final String stagingPath;

  const StagedRecording({
    required this.noteId,
    required this.assetId,
    required this.relativePath,
    required this.stagingPath,
  });
}
