import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/domain/document.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/asr/local_speech_recognizer.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';

class _FakeRecognizer implements LocalSpeechRecognizer {
  String nextText = 'распознанный текст';
  Object? nextError;

  @override
  String get engineId => 'fake';

  @override
  Future<TranscriptionResult> transcribeFile(
    String audioPath, {
    String languageHint = '',
  }) async {
    final error = nextError;
    if (error != null) throw error;
    return TranscriptionResult(
      text: nextText,
      modelId: 'fake-model',
      language: 'ru',
      audioDuration: const Duration(seconds: 1),
      processingTime: const Duration(milliseconds: 10),
    );
  }
}

void main() {
  late AppDatabase db;
  late Directory temp;
  late _FakeRecognizer recognizer;
  late NotesService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_service_test');
    recognizer = _FakeRecognizer();
    service = NotesService(
      db: db,
      media: MediaStore(temp),
      recognizer: recognizer,
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<StagedRecording> recordedNote() async {
    final staged = await service.beginAudioNote(extension: 'wav');
    await File(staged.stagingPath).writeAsBytes(List.filled(64, 7));
    await service.finishAudioNote(
      staged,
      duration: const Duration(seconds: 3),
      codec: 'pcm16-wav',
      sampleRateHz: 16000,
      channels: 1,
    );
    return staged;
  }

  group('text notes', () {
    test('createTextNote persists document envelope and projection', () async {
      await service.createTextNote('  привет  ');
      final notes = await service.watchNotes().first;
      expect(notes, hasLength(1));
      expect(notes.single.documentPlainText, 'привет');
      expect(notes.single.status, NoteStatus.inWork);
      expect(PotokDocument.decode(notes.single.documentJson).plainText, 'привет');
    });

    test('rejects empty text', () async {
      expect(() => service.createTextNote('   '), throwsArgumentError);
    });

    test('toggleDone flips status with optimistic revision bump', () async {
      await service.createTextNote('x');
      var note = (await service.watchNotes().first).single;
      await service.toggleDone(note);
      note = (await service.watchNotes().first).single;
      expect(note.status, NoteStatus.done);
      expect(note.completedAtUtc, isNotNull);
      expect(note.revision, 2);
    });
  });

  group('audio lifecycle', () {
    test('staged note is invisible until finalized', () async {
      final staged = await service.beginAudioNote(extension: 'wav');
      expect(await service.watchNotes().first, isEmpty);
      await File(staged.stagingPath).writeAsBytes([1, 2, 3]);
      await service.finishAudioNote(
        staged,
        duration: const Duration(seconds: 1),
        codec: 'pcm16-wav',
        sampleRateHz: 16000,
        channels: 1,
      );
      final notes = await service.watchNotes().first;
      expect(notes, hasLength(1));
      final asset = await service.watchReadyAudioAsset(staged.noteId).first;
      expect(asset, isNotNull);
      expect(asset!.lifecycleState, AssetLifecycle.ready);
      expect(asset.sha256, isNotNull);
    });

    test('finalize with missing bytes leaves no visible state', () async {
      final staged = await service.beginAudioNote(extension: 'wav');
      await expectLater(
        service.finishAudioNote(
          staged,
          duration: Duration.zero,
          codec: 'pcm16-wav',
          sampleRateHz: 16000,
          channels: 1,
        ),
        throwsA(isA<MediaFinalizeException>()),
      );
      expect(await service.watchNotes().first, isEmpty);
    });

    test('abort removes staged rows and bytes', () async {
      final staged = await service.beginAudioNote(extension: 'wav');
      await File(staged.stagingPath).writeAsBytes([1]);
      await service.abortAudioNote(staged);
      expect(await service.watchNotes().first, isEmpty);
      expect(File(staged.stagingPath).existsSync(), isFalse);
    });
  });

  group('transcription', () {
    test('success creates ready revision; accept appends paragraph once',
        () async {
      final staged = await recordedNote();
      final revision = await service.transcribe(staged.noteId, staged.assetId);
      expect(revision.state, TranscriptState.ready);
      expect(revision.rawText, 'распознанный текст');

      await service.acceptTranscript(staged.noteId, revision.id);
      final note = (await service.watchNotes().first).single;
      expect(note.documentPlainText, 'распознанный текст');
      expect(note.revision, 2);

      final revisions = await service.watchRevisions(staged.noteId).first;
      expect(revisions.single.acceptedAtUtc, isNotNull);
    });

    test('engine failure records failed revision and rethrows', () async {
      final staged = await recordedNote();
      recognizer.nextError = Exception('boom');
      await expectLater(
        service.transcribe(staged.noteId, staged.assetId),
        throwsException,
      );
      final revisions = await service.watchRevisions(staged.noteId).first;
      expect(revisions.single.state, TranscriptState.failed);
    });

    test('missing model records waiting_for_model', () async {
      final staged = await recordedNote();
      recognizer.nextError = const ModelUnavailableException('no model');
      await expectLater(
        service.transcribe(staged.noteId, staged.assetId),
        throwsA(isA<ModelUnavailableException>()),
      );
      final revisions = await service.watchRevisions(staged.noteId).first;
      expect(revisions.single.state, TranscriptState.waitingForModel);
    });

    test('re-transcription creates a second revision, originals kept',
        () async {
      final staged = await recordedNote();
      final first = await service.transcribe(staged.noteId, staged.assetId);
      recognizer.nextText = 'другая модель';
      final second = await service.transcribe(staged.noteId, staged.assetId);
      final revisions = await service.watchRevisions(staged.noteId).first;
      expect(revisions, hasLength(2));
      expect({first.id, second.id}, hasLength(2));
    });
  });
}
