import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/drafts_service.dart';
import 'package:potok/application/note_list_query.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/application/sessions_service.dart';
import 'package:potok/application/settings_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/infrastructure/audio_recorder.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';
import 'package:potok/infrastructure/recording_platform.dart';
import 'package:potok/presentation/capture_sheet.dart';
import 'package:potok/presentation/providers.dart';
import 'package:potok/presentation/sidebar.dart';
import 'package:potok/presentation/theme.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late SessionsService sessions;
  late NotesService notes;

  const project = Project(
    id: 'project-1',
    name: 'Проект',
    description: '',
    colorArgb: 0xFF4E75DB,
    isPinned: false,
    isArchived: false,
    createdAtUtc: 1,
    updatedAtUtc: 1,
    revision: 1,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_session_widget');
    clock = FixedClock(DateTime.utc(2026, 7, 17, 10));
    ids = SequentialIdGenerator();
    sessions = SessionsService(
      db: db,
      clock: clock,
      ids: ids,
      deviceId: 'device-test',
    );
    notes = NotesService(
      db: db,
      media: MediaStore(temp),
      clock: clock,
      ids: ids,
      deviceId: 'device-test',
    );
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: project.id,
            name: project.name,
            colorArgb: project.colorArgb,
            createdAtUtc: 1,
            updatedAtUtc: 1,
          ),
        );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  testWidgets('sidebar starts a named session for a project', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          navigationSummaryProvider.overrideWith(
            (ref) => Stream.value(NavigationSummary.empty),
          ),
          projectNoteCountsProvider.overrideWith(
            (ref) => Stream.value(const <String, int>{}),
          ),
          projectsProvider.overrideWith((ref) => Stream.value(const [project])),
          smartViewsProvider.overrideWith((ref) => Stream.value(const [])),
          currentSessionProvider.overrideWith((ref) => Stream.value(null)),
          sessionsServiceProvider.overrideWith((ref) => sessions),
        ],
        child: MaterialApp(
          theme: buildPotokTheme(PotokThemeId.studio),
          home: const Scaffold(body: Sidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Начать сессию'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('session-title')),
      'Интервью',
    );
    await tester.tap(find.byKey(const ValueKey('start-session')));
    await tester.pumpAndSettle();

    final current = await db.select(db.sessions).getSingleOrNull();
    expect(current, isNotNull);
    expect(current!.projectId, project.id);
    expect(current.title, 'Интервью');
  });

  testWidgets('session capture atomically links text note', (tester) async {
    final sessionId = await sessions.start(
      projectId: project.id,
      title: 'Тест-сессия',
    );
    final session = await db.select(db.sessions).getSingle();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesServiceProvider.overrideWith((ref) => notes),
          projectsProvider.overrideWith((ref) => Stream.value(const [project])),
          currentSessionProvider.overrideWith((ref) => Stream.value(session)),
          draftsServiceProvider.overrideWithValue(
            DraftsService(db: db, clock: clock),
          ),
        ],
        child: MaterialApp(
          theme: buildPotokTheme(PotokThemeId.studio),
          home: Scaffold(body: CaptureSheet(sessionId: sessionId)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Наблюдение в сессии');
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();

    final note = await db.select(db.notes).getSingle();
    expect(note.projectId, project.id);
    expect(note.sessionId, sessionId);
    expect(note.documentPlainText, 'Наблюдение в сессии');
  });

  testWidgets('session history shows absolute chronology and start offset', (
    tester,
  ) async {
    final sessionId = await sessions.start(
      projectId: project.id,
      title: 'Интервью',
    );
    await notes.createTextNote('Первая запись', sessionId: sessionId);
    clock.advance(const Duration(minutes: 14, seconds: 32));
    await notes.createTextNote('Вторая запись', sessionId: sessionId);
    final session = await db.select(db.sessions).getSingle();
    final timelineNotes =
        await (db.select(db.notes)
              ..where((row) => row.sessionId.equals(sessionId))
              ..orderBy([(row) => OrderingTerm.asc(row.createdAtUtc)]))
            .get();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          navigationSummaryProvider.overrideWith(
            (ref) => Stream.value(NavigationSummary.empty),
          ),
          projectNoteCountsProvider.overrideWith(
            (ref) => Stream.value(const <String, int>{}),
          ),
          projectsProvider.overrideWith((ref) => Stream.value(const [project])),
          smartViewsProvider.overrideWith((ref) => Stream.value(const [])),
          currentSessionProvider.overrideWith((ref) => Stream.value(session)),
          sessionsProvider.overrideWith((ref) => Stream.value([session])),
          sessionNotesProvider.overrideWith(
            (ref, id) => Stream.value(timelineNotes),
          ),
          sessionsServiceProvider.overrideWith((ref) => sessions),
        ],
        child: MaterialApp(
          theme: buildPotokTheme(PotokThemeId.studio),
          home: const Scaffold(body: Sidebar()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('История сессий'));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const ValueKey('session-timeline')), findsOneWidget);
    expect(find.text('Первая запись'), findsOneWidget);
    expect(find.text('Вторая запись'), findsOneWidget);
    expect(find.text('+00:00:00'), findsOneWidget);
    expect(find.text('+00:14:32'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('AAC recording supports pause/resume and keeps comment', (
    tester,
  ) async {
    final recorder = _FakeAudioRecorder();
    final recordingPlatform = _FakeRecordingPlatform();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesServiceProvider.overrideWith((ref) => notes),
          projectsProvider.overrideWith((ref) => Stream.value(const [project])),
          currentSessionProvider.overrideWith((ref) => Stream.value(null)),
          draftsServiceProvider.overrideWithValue(
            DraftsService(db: db, clock: clock),
          ),
          audioRecorderFactoryProvider.overrideWithValue(() => recorder),
          recordingPlatformProvider.overrideWithValue(recordingPlatform),
          settingsServiceProvider.overrideWithValue(SettingsService(db: db)),
        ],
        child: MaterialApp(
          theme: buildPotokTheme(PotokThemeId.studio),
          home: const Scaffold(body: CaptureSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Комментарий к записи');
    final mic = find.byKey(const ValueKey('recording-mic'));
    await tester.ensureVisible(mic);
    final startTap = tester.widget<InkWell>(mic).onTap;
    expect(startTap, isNotNull);
    await tester.runAsync(() async {
      startTap!();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(recorder.startedPath, endsWith('.m4a.partial'));
    expect(recorder.bitRate, 64000);
    expect(find.byKey(const ValueKey('recording-level')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recording-pause-resume')));
    expect(recorder.pauseCalls, 1);
    await tester.tap(find.byKey(const ValueKey('recording-pause-resume')));
    expect(recorder.resumeCalls, 1);
    await tester.runAsync(() async {
      tester.widget<InkWell>(mic).onTap!();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final saved = await db.select(db.notes).getSingle();
    final recording = await db.select(db.audioRecordings).getSingle();
    expect(saved.documentPlainText, 'Комментарий к записи');
    expect(recording.codec, 'aac-lc');
    expect(recording.sampleRateHz, 44100);
    expect(
      recordingPlatform.activeChanges.where((value) => value),
      hasLength(1),
    );
    expect(recordingPlatform.activeChanges.first, isTrue);
    expect(recordingPlatform.activeChanges.last, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('recording does not start when managed storage is low', (
    tester,
  ) async {
    final recorder = _FakeAudioRecorder();
    final recordingPlatform = _FakeRecordingPlatform(freeBytesValue: 1024);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesServiceProvider.overrideWith((ref) => notes),
          projectsProvider.overrideWith((ref) => Stream.value(const [project])),
          currentSessionProvider.overrideWith((ref) => Stream.value(null)),
          draftsServiceProvider.overrideWithValue(
            DraftsService(db: db, clock: clock),
          ),
          audioRecorderFactoryProvider.overrideWithValue(() => recorder),
          recordingPlatformProvider.overrideWithValue(recordingPlatform),
          settingsServiceProvider.overrideWithValue(SettingsService(db: db)),
        ],
        child: MaterialApp(
          theme: buildPotokTheme(PotokThemeId.studio),
          home: const Scaffold(body: CaptureSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mic = find.byKey(const ValueKey('recording-mic'));
    await tester.runAsync(() async {
      tester.widget<InkWell>(mic).onTap!();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.text('Недостаточно места для начала записи'), findsOneWidget);
    expect(recorder.startedPath, isNull);
    expect(recordingPlatform.activeChanges, isEmpty);
    expect(await db.select(db.notes).get(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('capture adds audio to an existing note without replacing text', (
    tester,
  ) async {
    final noteId = await notes.createTextNote('Текст остаётся');
    final note = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(noteId))).getSingle();
    final recorder = _FakeAudioRecorder();
    final recordingPlatform = _FakeRecordingPlatform();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesServiceProvider.overrideWith((ref) => notes),
          projectsProvider.overrideWith((ref) => Stream.value(const [project])),
          currentSessionProvider.overrideWith((ref) => Stream.value(null)),
          draftsServiceProvider.overrideWithValue(
            DraftsService(db: db, clock: clock),
          ),
          audioRecorderFactoryProvider.overrideWithValue(() => recorder),
          recordingPlatformProvider.overrideWithValue(recordingPlatform),
          settingsServiceProvider.overrideWithValue(SettingsService(db: db)),
        ],
        child: MaterialApp(
          theme: buildPotokTheme(PotokThemeId.studio),
          home: Scaffold(body: CaptureSheet(attachToNote: note)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Добавить аудио'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    final mic = find.byKey(const ValueKey('recording-mic'));
    await tester.runAsync(() async {
      tester.widget<InkWell>(mic).onTap!();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() async {
      tester.widget<InkWell>(mic).onTap!();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 300));

    final updated = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(noteId))).getSingle();
    expect(updated.documentPlainText, 'Текст остаётся');
    expect(updated.revision, 2);
    expect(await db.select(db.mediaAssets).get(), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _FakeRecordingPlatform implements RecordingPlatformPort {
  final activeChanges = <bool>[];
  final int freeBytesValue;

  _FakeRecordingPlatform({this.freeBytesValue = 1024 * 1024 * 1024});

  @override
  Future<int?> freeBytes(String managedPath) async => freeBytesValue;

  @override
  Future<void> setRecordingActive(bool active) async {
    activeChanges.add(active);
  }
}

class _FakeAudioRecorder implements AudioRecorderPort {
  final _levels = StreamController<RecorderLevel>.broadcast();
  String? startedPath;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int? bitRate;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _levels.close();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Stream<RecorderLevel> levels() => _levels.stream;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> resume() async => resumeCalls++;

  @override
  Future<void> startM4a(String path, {required int bitRate}) async {
    startedPath = path;
    this.bitRate = bitRate;
    await File(path).writeAsBytes([
      0,
      0,
      0,
      24,
      0x66,
      0x74,
      0x79,
      0x70,
      0x4D,
      0x34,
      0x41,
      0x20,
      ...List.filled(64, 1),
    ]);
    _levels.add(const RecorderLevel(0.5));
  }

  @override
  Future<String?> stop() async => startedPath;
}
