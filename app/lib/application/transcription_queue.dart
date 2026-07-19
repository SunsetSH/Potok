import 'dart:async';

import 'package:drift/drift.dart';

import '../domain/clock.dart';
import '../domain/id_generator.dart';
import '../domain/types.dart';
import '../infrastructure/asr/local_speech_recognizer.dart';
import '../infrastructure/asr/model_manager.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/media_store.dart';

/// Создаёт движок под конкретную папку модели (активная модель может
/// смениться между job'ами).
typedef RecognizerFactory = LocalSpeechRecognizer Function(String modelDir);

/// Durable-очередь локальной расшифровки (FR-ASR-002, ADR-002).
///
/// Состояние очереди — строки TranscriptRevisions: процесс может умереть в
/// любой точке, [recoverOnStartup] возвращает зависшие job'ы в работу.
/// Worker один на процесс и обрабатывает queued по одному (FIFO по
/// createdAtUtc); сам ASR идёт в изоляте движка, UI-поток не блокируется.
///
/// Переходы: queued → recognizing → ready | failed | waitingForModel.
/// cancel: queued/recognizing → cancelled; запущенный изолят не прерывается,
/// но его результат отбрасывается (все финальные записи guarded по
/// state == recognizing, поэтому cancelled не перезаписывается).
class TranscriptionQueue {
  final AppDatabase db;
  final MediaStore media;
  final ActiveModelLocator models;
  final RecognizerFactory recognizerFactory;
  final String engineId;
  final Clock clock;
  final IdGenerator ids;
  final Future<void> Function(String noteId, String text)? onTranscriptReady;

  Future<void>? _worker;
  bool _wake = false;

  TranscriptionQueue({
    required this.db,
    required this.media,
    required this.models,
    required this.recognizerFactory,
    required this.engineId,
    required this.clock,
    required this.ids,
    this.onTranscriptReady,
  });

  /// Ставит расшифровку в очередь: создаёт TranscriptRevision(queued) и
  /// будит worker. Возвращает id ревизии.
  Future<String> enqueue(
    String noteId,
    String assetId, {
    String language = '',
  }) async {
    final revisionId = ids.newId();
    await db.transaction(() async {
      await db
          .into(db.transcriptRevisions)
          .insert(
            TranscriptRevisionsCompanion.insert(
              id: revisionId,
              noteId: noteId,
              audioAssetId: assetId,
              engineId: engineId,
              modelId: '',
              language: language,
              state: TranscriptState.queued,
              createdAtUtc: clock.nowUtcMillis(),
            ),
          );
    });
    _ping();
    return revisionId;
  }

  /// Повтор для failed/cancelled: НОВАЯ ревизия через [enqueue], старая
  /// не изменяется (ТЗ: ревизии не уничтожаются).
  Future<String> retry(String revisionId) async {
    final revision = await (db.select(
      db.transcriptRevisions,
    )..where((r) => r.id.equals(revisionId))).getSingle();
    if (revision.state != TranscriptState.failed &&
        revision.state != TranscriptState.cancelled) {
      throw StateError('only failed or cancelled revisions can be retried');
    }
    return enqueue(
      revision.noteId,
      revision.audioAssetId,
      language: revision.language,
    );
  }

  /// queued/recognizing/waitingForModel → cancelled. Возвращает false, если ревизия уже в
  /// финальном состоянии. Изолят recognizing не прерывается — его результат
  /// отбрасывает stale-guard.
  Future<bool> cancel(String revisionId) async {
    final changed =
        await (db.update(db.transcriptRevisions)..where(
              (r) =>
                  r.id.equals(revisionId) &
                  r.state.isInValues(const [
                    TranscriptState.queued,
                    TranscriptState.recognizing,
                    TranscriptState.waitingForModel,
                  ]),
            ))
            .write(
              const TranscriptRevisionsCompanion(
                state: Value(TranscriptState.cancelled),
              ),
            );
    return changed > 0;
  }

  /// Ревизии, зависшие в recognizing после краха процесса, возвращаются в
  /// queued. Вызывается один раз при старте приложения.
  Future<void> recoverOnStartup() async {
    await (db.update(
      db.transcriptRevisions,
    )..where((r) => r.state.equalsValue(TranscriptState.recognizing))).write(
      const TranscriptRevisionsCompanion(state: Value(TranscriptState.queued)),
    );
    _ping();
  }

  /// После активации модели: waitingForModel → queued и запуск worker'а.
  Future<void> kick() async {
    await (db.update(db.transcriptRevisions)
          ..where((r) => r.state.equalsValue(TranscriptState.waitingForModel)))
        .write(
          const TranscriptRevisionsCompanion(
            state: Value(TranscriptState.queued),
          ),
        );
    _ping();
  }

  /// Завершение текущего прохода worker'а (для тестов и graceful shutdown).
  Future<void> idle() => _worker ?? Future<void>.value();

  void _ping() {
    _wake = true;
    _worker ??= _run().whenComplete(() {
      _worker = null;
      // Пробуждение между последней проверкой _wake и завершением future
      // не должно теряться.
      if (_wake) _ping();
    });
  }

  Future<void> _run() async {
    while (_wake) {
      _wake = false;
      while (true) {
        final next =
            await (db.select(db.transcriptRevisions)
                  ..where((r) => r.state.equalsValue(TranscriptState.queued))
                  ..orderBy([
                    (r) => OrderingTerm.asc(r.createdAtUtc),
                    (r) => OrderingTerm.asc(r.id),
                  ])
                  ..limit(1))
                .getSingleOrNull();
        if (next == null) break;
        try {
          await _process(next);
        } catch (e) {
          // Инфраструктурный сбой вне _process-обработки (например, сама БД):
          // помечаем failed, а при недоступной БД выходим, чтобы не крутить
          // горячий цикл по той же строке.
          final moved = await _tryMarkFailed(next.id, e);
          if (!moved) return;
        }
      }
    }
  }

  Future<void> _process(TranscriptRevision revision) async {
    final modelDir = await models.activeModelDir();
    if (modelDir == null) {
      // Без попытки распознавания; kick() после активации вернёт в queued.
      await _transition(
        revision.id,
        from: TranscriptState.queued,
        to: TranscriptState.waitingForModel,
      );
      return;
    }
    final claimed =
        await _transition(
          revision.id,
          from: TranscriptState.queued,
          to: TranscriptState.recognizing,
        ) >
        0;
    if (!claimed) return; // отменили, пока стояла в очереди
    final asset = await (db.select(
      db.mediaAssets,
    )..where((a) => a.id.equals(revision.audioAssetId))).getSingleOrNull();
    if (asset == null) {
      await _transition(
        revision.id,
        from: TranscriptState.recognizing,
        to: TranscriptState.failed,
        error: 'audio asset not found',
      );
      return;
    }
    try {
      final result = await recognizerFactory(modelDir).transcribeFile(
        media.absolutePath(asset.relativePath),
        languageHint: revision.language,
      );
      // Stale-guard: ready пишется только поверх recognizing — результат
      // отменённой job не перезаписывает cancelled.
      final changed =
          await (db.update(db.transcriptRevisions)..where(
                (r) =>
                    r.id.equals(revision.id) &
                    r.state.equalsValue(TranscriptState.recognizing),
              ))
              .write(
                TranscriptRevisionsCompanion(
                  rawText: Value(result.text),
                  modelId: Value(result.modelId),
                  language: Value(result.language),
                  state: const Value(TranscriptState.ready),
                  errorMessage: const Value(null),
                ),
              );
      if (changed > 0 && result.text.trim().isNotEmpty) {
        try {
          await onTranscriptReady?.call(revision.noteId, result.text);
        } catch (_) {
          // Ревизия уже ready: сбой колбэка (например, гонка ревизий заметки)
          // не должен ни валить job, ни останавливать очередь.
        }
      }
    } on ModelUnavailableException {
      // Модель пропала между activeModelDir() и запуском движка.
      await _transition(
        revision.id,
        from: TranscriptState.recognizing,
        to: TranscriptState.waitingForModel,
      );
    } catch (e) {
      await _transition(
        revision.id,
        from: TranscriptState.recognizing,
        to: TranscriptState.failed,
        error: e.toString(),
      );
    }
  }

  Future<int> _transition(
    String revisionId, {
    required TranscriptState from,
    required TranscriptState to,
    String? error,
  }) {
    return (db.update(
      db.transcriptRevisions,
    )..where((r) => r.id.equals(revisionId) & r.state.equalsValue(from))).write(
      TranscriptRevisionsCompanion(
        state: Value(to),
        errorMessage: Value(error),
      ),
    );
  }

  Future<bool> _tryMarkFailed(String revisionId, Object cause) async {
    try {
      final changed =
          await (db.update(db.transcriptRevisions)..where(
                (r) =>
                    r.id.equals(revisionId) &
                    r.state.isInValues(const [
                      TranscriptState.queued,
                      TranscriptState.recognizing,
                    ]),
              ))
              .write(
                TranscriptRevisionsCompanion(
                  state: const Value(TranscriptState.failed),
                  errorMessage: Value(cause.toString()),
                ),
              );
      return changed > 0;
    } catch (_) {
      return false;
    }
  }
}
