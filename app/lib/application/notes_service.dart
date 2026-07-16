import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/document.dart';
import '../domain/types.dart';
import '../infrastructure/asr/local_speech_recognizer.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/media_store.dart';

/// Use cases of the vertical slice. Every mutation is a single transaction:
/// it either completes fully or leaves no visible state (ТЗ 0.9).
class NotesService {
  final AppDatabase db;
  final MediaStore media;
  final LocalSpeechRecognizer recognizer;
  final Uuid _uuid = const Uuid();

  NotesService({
    required this.db,
    required this.media,
    required this.recognizer,
  });

  int _nowUtc() => DateTime.now().toUtc().millisecondsSinceEpoch;

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

  Future<String> createTextNote(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('note text must not be empty');
    }
    final document = PotokDocument.fromPlainText(trimmed);
    final id = _uuid.v7();
    final now = _nowUtc();
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
    return id;
  }

  /// Registers a staged recording and returns the absolute path the recorder
  /// must write to. DB row is created in `staging` before any bytes exist.
  Future<StagedRecording> beginAudioNote({required String extension}) async {
    final noteId = _uuid.v7();
    final assetId = _uuid.v7();
    final relativePath = media.relativePathFor(assetId, extension);
    await media.prepareStaging(relativePath);
    final now = _nowUtc();
    await db.transaction(() async {
      await db.into(db.notes).insert(
            NotesCompanion.insert(
              id: noteId,
              documentJson: const PotokDocument.empty().encode(),
              documentPlainText: '',
              sourceKind: SourceKind.audio,
              createdAtUtc: now,
              updatedAtUtc: now,
              // Hidden from lists until the recording is finalized.
              deletedAtUtc: Value(now),
            ),
          );
      await db.into(db.mediaAssets).insert(
            MediaAssetsCompanion.insert(
              id: assetId,
              ownerNoteId: noteId,
              kind: AssetKind.audio,
              relativePath: relativePath,
              mimeType: 'audio/wav',
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

  /// Finalize protocol: validate + hash + atomic rename, then a short DB
  /// commit flips asset to `ready` and makes the note visible (FR-AUD-002).
  Future<void> finishAudioNote(
    StagedRecording staged, {
    required Duration duration,
    required String codec,
    required int sampleRateHz,
    required int channels,
  }) async {
    final result = await media.finalize(staged.relativePath);
    final now = _nowUtc();
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
    });
  }

  /// Cancelled/failed recording: discard staged bytes, keep no visible note.
  Future<void> abortAudioNote(StagedRecording staged) async {
    await media.discardStaging(staged.relativePath);
    await db.transaction(() async {
      await (db.delete(db.mediaAssets)..where((a) => a.id.equals(staged.assetId)))
          .go();
      await (db.delete(db.notes)..where((n) => n.id.equals(staged.noteId))).go();
    });
  }

  /// Runs local ASR for a ready audio asset. Each attempt creates a new
  /// TranscriptRevision; user text is never touched here (FR-ASR-003/004).
  Future<TranscriptRevision> transcribe(
    String noteId,
    String assetId, {
    String languageHint = '',
  }) async {
    final asset = await (db.select(db.mediaAssets)
          ..where((a) => a.id.equals(assetId)))
        .getSingle();
    final revisionId = _uuid.v7();
    await db.into(db.transcriptRevisions).insert(
          TranscriptRevisionsCompanion.insert(
            id: revisionId,
            noteId: noteId,
            audioAssetId: assetId,
            engineId: recognizer.engineId,
            modelId: '',
            language: languageHint,
            state: TranscriptState.recognizing,
            createdAtUtc: _nowUtc(),
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

  /// Explicit user acceptance: transcript is appended to the document,
  /// never replacing existing content (FR-ASR-004). Optimistic concurrency
  /// via revision guard (ТЗ 0.9).
  Future<void> acceptTranscript(String noteId, String revisionId) async {
    await db.transaction(() async {
      final note = await (db.select(db.notes)..where((n) => n.id.equals(noteId)))
          .getSingle();
      final revision = await (db.select(db.transcriptRevisions)
            ..where((r) => r.id.equals(revisionId)))
          .getSingle();
      if (revision.state != TranscriptState.ready) {
        throw StateError('transcript is not ready');
      }
      final document =
          PotokDocument.decode(note.documentJson).appendParagraph(revision.rawText);
      final now = _nowUtc();
      final updated = await (db.update(db.notes)
            ..where((n) => n.id.equals(noteId) & n.revision.equals(note.revision)))
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
    });
  }

  Future<void> toggleDone(Note note) async {
    final now = _nowUtc();
    final next =
        note.status == NoteStatus.done ? NoteStatus.inWork : NoteStatus.done;
    await (db.update(db.notes)
          ..where((n) => n.id.equals(note.id) & n.revision.equals(note.revision)))
        .write(NotesCompanion(
      status: Value(next),
      completedAtUtc: Value(next == NoteStatus.done ? now : null),
      updatedAtUtc: Value(now),
      revision: Value(note.revision + 1),
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
