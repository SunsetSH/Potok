import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/application/transcription_queue.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/asr/local_speech_recognizer.dart';
import 'package:potok/infrastructure/asr/model_manager.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';

class _FakeModels implements ActiveModelLocator {
  String? dir;

  _FakeModels([this.dir]);

  @override
  Future<String?> activeModelDir() async => dir;
}

class _FakeRecognizer implements LocalSpeechRecognizer {
  String nextText = 'распознанный текст';
  Object? nextError;

  /// Если задан — transcribeFile блокируется до его завершения
  /// (детерминированные тесты cancel/stale-guard).
  Completer<void>? gate;

  /// Завершается при первом входе в transcribeFile.
  final Completer<void> started = Completer<void>();

  int calls = 0;
  String? lastPath;

  @override
  String get engineId => 'fake';

  @override
  Future<TranscriptionResult> transcribeFile(
    String audioPath, {
    String languageHint = '',
  }) async {
    calls++;
    lastPath = audioPath;
    if (!started.isCompleted) started.complete();
    final g = gate;
    if (g != null) await g.future;
    final error = nextError;
    if (error != null) throw error;
    return TranscriptionResult(
      text: nextText,
      modelId: 'fake-model',
      language: 'ru',
      audioDuration: const Duration(seconds: 1),
      processingTime: const Duration(milliseconds: 5),
    );
  }
}

void main() {
  late AppDatabase db;
  late Directory temp;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late NotesService notes;
  late _FakeModels models;
  late _FakeRecognizer recognizer;
  late TranscriptionQueue queue;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_queue_test');
    clock = FixedClock(DateTime.utc(2026, 7, 17, 10));
    ids = SequentialIdGenerator();
    final media = MediaStore(temp);
    notes = NotesService(
      db: db,
      media: media,
      clock: clock,
      ids: ids,
      deviceId: 'device-test',
    );
    models = _FakeModels('model-dir');
    recognizer = _FakeRecognizer();
    queue = TranscriptionQueue(
      db: db,
      media: media,
      models: models,
      recognizerFactory: (_) => recognizer,
      engineId: 'fake',
      clock: clock,
      ids: ids,
    );
  });

  tearDown(() async {
    await queue.idle();
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<StagedRecording> recordedNote() async {
    final staged = await notes.beginAudioNote(extension: 'wav');
    await File(staged.stagingPath).writeAsBytes(List.filled(64, 7));
    await notes.finishAudioNote(
      staged,
      duration: const Duration(seconds: 3),
      codec: 'pcm16-wav',
      sampleRateHz: 16000,
      channels: 1,
    );
    return staged;
  }

  Future<TranscriptRevision> revisionById(String id) =>
      (db.select(db.transcriptRevisions)..where((r) => r.id.equals(id)))
          .getSingle();

  test('enqueue -> worker -> ready with rawText, modelId and language',
      () async {
    final staged = await recordedNote();
    final id = await queue.enqueue(staged.noteId, staged.assetId);
    await queue.idle();

    final revision = await revisionById(id);
    expect(revision.state, TranscriptState.ready);
    expect(revision.rawText, 'распознанный текст');
    expect(revision.modelId, 'fake-model');
    expect(revision.language, 'ru');
    expect(revision.errorMessage, isNull);
    expect(recognizer.lastPath, contains(staged.assetId));
  });

  test('engine failure -> failed with errorMessage; retry creates new revision',
      () async {
    final staged = await recordedNote();
    recognizer.nextError = Exception('boom');
    final firstId = await queue.enqueue(staged.noteId, staged.assetId);
    await queue.idle();

    final failed = await revisionById(firstId);
    expect(failed.state, TranscriptState.failed);
    expect(failed.errorMessage, contains('boom'));

    recognizer.nextError = null;
    final secondId = await queue.retry(firstId);
    expect(secondId, isNot(firstId));
    await queue.idle();

    expect((await revisionById(firstId)).state, TranscriptState.failed,
        reason: 'старая ревизия не изменяется');
    expect((await revisionById(secondId)).state, TranscriptState.ready);
  });

  test('retry is rejected for non-terminal revisions', () async {
    final staged = await recordedNote();
    final id = await queue.enqueue(staged.noteId, staged.assetId);
    await queue.idle(); // ready
    await expectLater(queue.retry(id), throwsStateError);
  });

  test('no model -> waitingForModel without recognition; kick requeues',
      () async {
    models.dir = null;
    final staged = await recordedNote();
    final id = await queue.enqueue(staged.noteId, staged.assetId);
    await queue.idle();

    expect((await revisionById(id)).state, TranscriptState.waitingForModel);
    expect(recognizer.calls, 0, reason: 'без модели распознавание не идёт');

    models.dir = 'model-dir';
    await queue.kick();
    await queue.idle();
    expect((await revisionById(id)).state, TranscriptState.ready);
  });

  test('recoverOnStartup returns crashed recognizing jobs to the pipeline',
      () async {
    final staged = await recordedNote();
    final id = ids.newId();
    await db.into(db.transcriptRevisions).insert(
          TranscriptRevisionsCompanion.insert(
            id: id,
            noteId: staged.noteId,
            audioAssetId: staged.assetId,
            engineId: 'fake',
            modelId: '',
            language: '',
            state: TranscriptState.recognizing,
            createdAtUtc: clock.nowUtcMillis(),
          ),
        );

    // Без модели: recognizing -> queued -> waitingForModel, то есть job
    // снова в конвейере, а не завис навсегда.
    models.dir = null;
    await queue.recoverOnStartup();
    await queue.idle();
    expect((await revisionById(id)).state, TranscriptState.waitingForModel);

    // С моделью восстановленная job доводится до ready.
    models.dir = 'model-dir';
    await queue.kick();
    await queue.idle();
    expect((await revisionById(id)).state, TranscriptState.ready);
  });

  test('cancel queued -> cancelled and worker skips it', () async {
    final staged = await recordedNote();
    recognizer.gate = Completer<void>();
    final blockedId = await queue.enqueue(staged.noteId, staged.assetId);
    await recognizer.started.future; // worker занят первой job
    final queuedId = await queue.enqueue(staged.noteId, staged.assetId);

    expect(await queue.cancel(queuedId), isTrue);
    expect((await revisionById(queuedId)).state, TranscriptState.cancelled);

    recognizer.gate!.complete();
    await queue.idle();
    expect((await revisionById(blockedId)).state, TranscriptState.ready);
    expect((await revisionById(queuedId)).state, TranscriptState.cancelled);
    expect(recognizer.calls, 1, reason: 'отменённая job не распознаётся');
  });

  test('stale-guard: finished result of a cancelled job keeps cancelled',
      () async {
    final staged = await recordedNote();
    recognizer.gate = Completer<void>();
    final id = await queue.enqueue(staged.noteId, staged.assetId);
    await recognizer.started.future;
    expect((await revisionById(id)).state, TranscriptState.recognizing);

    expect(await queue.cancel(id), isTrue);
    recognizer.gate!.complete(); // изолят «дорабатывает» и приносит результат
    await queue.idle();

    final revision = await revisionById(id);
    expect(revision.state, TranscriptState.cancelled);
    expect(revision.rawText, isEmpty,
        reason: 'результат отменённой job отброшен');
  });

  test('cancel of a terminal revision is a no-op', () async {
    final staged = await recordedNote();
    final id = await queue.enqueue(staged.noteId, staged.assetId);
    await queue.idle();
    expect(await queue.cancel(id), isFalse);
    expect((await revisionById(id)).state, TranscriptState.ready);
  });
}
