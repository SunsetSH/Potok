import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/drafts_service.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/application/settings_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/document.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/audio_recorder.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';
import 'package:potok/infrastructure/recording_platform.dart';
import 'package:potok/presentation/app_shell.dart';
import 'package:potok/presentation/app_shortcuts.dart';
import 'package:potok/presentation/capture_sheet.dart';
import 'package:potok/presentation/note_detail_pane.dart';
import 'package:potok/presentation/providers.dart';
import 'package:potok/presentation/theme.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late NotesService notes;
  late Note note;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_shortcuts_test');
    notes = NotesService(
      db: db,
      media: MediaStore(temp),
      clock: FixedClock(DateTime.utc(2026, 7, 17, 12)),
      ids: SequentialIdGenerator(),
      deviceId: 'device-test',
    );
    final id = await notes.createTextNote('Проверить сценарий');
    note = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(id))).getSingle();
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Widget app(Widget home, {Note? selected}) {
    return ProviderScope(
      overrides: [
        notesServiceProvider.overrideWithValue(AsyncData(notes)),
        projectsProvider.overrideWith((ref) => Stream.value(const [])),
        draftsServiceProvider.overrideWithValue(
          DraftsService(db: db, clock: FixedClock(DateTime.utc(2026, 7, 17))),
        ),
        audioRecorderFactoryProvider.overrideWithValue(
          () => _FakeAudioRecorder(permission: true),
        ),
        recordingPlatformProvider.overrideWithValue(_FakeRecordingPlatform()),
        settingsServiceProvider.overrideWithValue(SettingsService(db: db)),
        noteTagsProvider.overrideWith((ref, id) => Stream.value(const [])),
        availableTagsProvider.overrideWith((ref, id) => Stream.value(const [])),
        audioAssetsProvider.overrideWith((ref, id) => Stream.value(const [])),
        revisionsProvider.overrideWith((ref, id) => Stream.value(const [])),
        mediaStoreProvider.overrideWithValue(AsyncData(MediaStore(temp))),
        if (selected != null)
          selectedNoteProvider.overrideWith((ref) => selected),
      ],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        scaffoldMessengerKey: appScaffoldMessengerKey,
        theme: buildPotokTheme(PotokThemeId.studio),
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('ru'), Locale('en')],
        builder: (context, child) =>
            AppShortcuts(child: child ?? const SizedBox.shrink()),
        home: home,
      ),
    );
  }

  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }

  testWidgets('Ctrl+N opens text quick capture even from a text field', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const Scaffold(body: TextField(autofocus: true))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await pressCtrl(tester, LogicalKeyboardKey.keyN);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Быстрая заметка'), findsOneWidget);
    expect(find.byKey(const ValueKey('recording-mic')), findsOneWidget);
  });

  testWidgets('Ctrl+K moves focus to search even from a text field', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Column(
              children: [
                const TextField(autofocus: true),
                TextField(focusNode: ref.watch(searchFocusProvider)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShortcuts)),
    );

    await pressCtrl(tester, LogicalKeyboardKey.keyK);
    await tester.pump();

    expect(container.read(searchFocusProvider).hasFocus, isTrue);
  });

  testWidgets('shared text preserves an existing draft and source kind', (
    tester,
  ) async {
    final drafts = DraftsService(
      db: db,
      clock: FixedClock(DateTime.utc(2026, 7, 17)),
    );
    await drafts.save(
      'quick-capture',
      documentJson: PotokDocument.fromPlainText('existing draft').encode(),
    );
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: CaptureSheet(
            initialText: 'shared text',
            sourceKind: SourceKind.share,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'existing draft\n\nshared text');
    expect(field.autofocus, isFalse);
    final storedDraft = await drafts.load('quick-capture');
    expect(
      PotokDocument.decode(storedDraft!.documentJson).plainText,
      'existing draft\n\nshared text',
    );

    await tester.tap(find.text('Готово'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final created = await (db.select(
      db.notes,
    )..where((row) => row.id.isNotValue(note.id))).getSingle();
    expect(created.sourceKind, SourceKind.share);
    expect(created.documentPlainText, 'existing draft\n\nshared text');
  });

  testWidgets('Esc unfocuses text first and then invokes route action', (
    tester,
  ) async {
    var escaped = 0;
    await tester.pumpWidget(
      app(
        EscapeScope(
          onEscape: () => escaped++,
          child: const Scaffold(body: TextField(autofocus: true)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(escaped, 0);
    expect(isTextEditingFocused(), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(escaped, 1);
  });

  testWidgets('dialog keeps its own Esc dismissal', (tester) async {
    var escaped = 0;
    await tester.pumpWidget(
      app(
        EscapeScope(
          onEscape: () => escaped++,
          child: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: Text('dialog')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('dialog'), findsNothing);
    expect(escaped, 0);
  });

  testWidgets('Ctrl+S flushes pending autosave without waiting for debounce', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const Scaffold(body: NoteDetailPane()), selected: note),
    );
    await tester.pumpAndSettle();

    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    controller.replaceText(
      0,
      0,
      'Срочно: ',
      const TextSelection.collapsed(offset: 8),
    );
    // Debounce (500 мс) ещё не истёк — на диске старая ревизия.
    await tester.pump(const Duration(milliseconds: 100));
    var stored = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(note.id))).getSingle();
    expect(stored.revision, note.revision);

    await pressCtrl(tester, LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();

    stored = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(note.id))).getSingle();
    expect(stored.revision, note.revision + 1);
    expect(stored.documentPlainText, startsWith('Срочно: '));
    expect(find.text('Все изменения сохранены'), findsOneWidget);
  });

  testWidgets('Delete inside a text field never trashes the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const Scaffold(body: TextField(autofocus: true))),
    );
    // Без pumpAndSettle: мигающий курсор TextField не даёт кадрам «устаканиться».
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShortcuts)),
    );
    container.read(selectedNoteIdProvider.notifier).select(note.id);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final stored = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(note.id))).getSingle();
    expect(stored.deletedAtUtc, isNull);
  });

  testWidgets('Delete outside text input trashes selection with undo', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(Scaffold(body: Focus(autofocus: true, child: Container()))),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShortcuts)),
    );
    container.read(selectedNoteIdProvider.notifier).select(note.id);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    var stored = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(note.id))).getSingle();
    expect(stored.deletedAtUtc, isNotNull);
    expect(container.read(selectedNoteIdProvider), isNull);

    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    stored = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(note.id))).getSingle();
    expect(stored.deletedAtUtc, isNull);
  });

  group('quick capture with audio autostart (Ctrl+Shift+N)', () {
    Widget capture(
      _FakeAudioRecorder recorder, {
      Future<void> Function(String noteId, String assetId, String fallbackText)?
      autoEnqueue,
      bool asrReady = false,
      Object? asrError,
    }) {
      return ProviderScope(
        overrides: [
          notesServiceProvider.overrideWith((ref) => notes),
          projectsProvider.overrideWith((ref) => Stream.value(const [])),
          draftsServiceProvider.overrideWithValue(
            DraftsService(db: db, clock: FixedClock(DateTime.utc(2026, 7, 17))),
          ),
          audioRecorderFactoryProvider.overrideWithValue(() => recorder),
          recordingPlatformProvider.overrideWithValue(_FakeRecordingPlatform()),
          settingsServiceProvider.overrideWithValue(SettingsService(db: db)),
          activeAsrModelDirectoryProvider.overrideWith((ref) async {
            if (asrError != null) throw asrError;
            return asrReady ? temp.path : null;
          }),
          if (autoEnqueue != null)
            automaticTranscriptionEnqueueProvider.overrideWithValue(
              autoEnqueue,
            ),
        ],
        child: MaterialApp(
          theme: buildPotokTheme(PotokThemeId.studio),
          home: const Scaffold(body: CaptureSheet(startWithAudio: true)),
        ),
      );
    }

    testWidgets('starts recording when microphone permission is granted', (
      tester,
    ) async {
      final recorder = _FakeAudioRecorder(permission: true);
      final enqueued = <(String, String)>[];
      await SettingsService(
        db: db,
      ).set(SettingsService.audioInputDeviceKey, 'microphone-1');
      // Автостарт идёт в post-frame callback первого кадра; staging делает
      // реальный файловый ввод-вывод, поэтому первый pump — внутри runAsync.
      await tester.runAsync(() async {
        await tester.pumpWidget(
          capture(
            recorder,
            autoEnqueue: (noteId, assetId, fallbackText) async {
              enqueued.add((noteId, assetId));
            },
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(recorder.startedPath, endsWith('.m4a.partial'));
      expect(recorder.inputDeviceId, 'microphone-1');
      expect(find.text('Остановить'), findsOneWidget);

      // Останавливаем и финализируем запись.
      await tester.runAsync(() async {
        tester
            .widget<InkWell>(find.byKey(const ValueKey('recording-mic')))
            .onTap!();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(await db.select(db.mediaAssets).get(), hasLength(1));
      final asset = (await db.select(db.mediaAssets).get()).single;
      expect(enqueued, [(asset.ownerNoteId, asset.id)]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('without permission shows error and stages nothing', (
      tester,
    ) async {
      final recorder = _FakeAudioRecorder(permission: false);
      await tester.pumpWidget(capture(recorder));
      await tester.pumpAndSettle();

      expect(find.text('Нет доступа к микрофону'), findsOneWidget);
      expect(recorder.startedPath, isNull);
      expect(await db.select(db.mediaAssets).get(), isEmpty);
    });

    testWidgets('model bootstrap failure does not block audio capture', (
      tester,
    ) async {
      final recorder = _FakeAudioRecorder(permission: true);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          capture(recorder, asrError: StateError('missing model asset')),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(recorder.startedPath, endsWith('.m4a.partial'));
      expect(find.textContaining('аудио сохранится'), findsOneWidget);
      await tester.runAsync(() async {
        tester
            .widget<InkWell>(find.byKey(const ValueKey('recording-mic')))
            .onTap!();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });

    testWidgets('active offline model records ASR-ready WAV', (tester) async {
      final recorder = _FakeAudioRecorder(permission: true);
      await tester.runAsync(() async {
        await tester.pumpWidget(capture(recorder, asrReady: true));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(recorder.startedPath, endsWith('.wav.partial'));
      expect(recorder.format, AudioRecordingFormat.wavPcm16);
      await tester.runAsync(() async {
        tester
            .widget<InkWell>(find.byKey(const ValueKey('recording-mic')))
            .onTap!();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Done finalizes an active Android-style recording', (
      tester,
    ) async {
      final recorder = _FakeAudioRecorder(permission: true);
      await tester.runAsync(() async {
        await tester.pumpWidget(capture(recorder));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Остановить'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Готово'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(await db.select(db.mediaAssets).get(), hasLength(1));
      expect((await db.select(db.notes).get()).length, 2);
    });
  });
}

class _FakeRecordingPlatform implements RecordingPlatformPort {
  @override
  Future<int?> freeBytes(String managedPath) async => 1024 * 1024 * 1024;

  @override
  Future<void> setRecordingActive(bool active) async {}
}

class _FakeAudioRecorder implements AudioRecorderPort {
  final bool permission;
  final _levels = StreamController<RecorderLevel>.broadcast();
  String? startedPath;
  AudioRecordingFormat? format;
  String? inputDeviceId;

  _FakeAudioRecorder({required this.permission});

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<List<AudioInputDevice>> listInputDevices() async => const [];

  @override
  Future<void> start(
    String path, {
    required AudioRecordingFormat format,
    required int bitRate,
    String? inputDeviceId,
  }) async {
    startedPath = path;
    this.format = format;
    this.inputDeviceId = inputDeviceId;
    await File(path).writeAsBytes(
      format == AudioRecordingFormat.wavPcm16
          ? [
              0x52,
              0x49,
              0x46,
              0x46,
              64,
              0,
              0,
              0,
              0x57,
              0x41,
              0x56,
              0x45,
              ...List.filled(64, 1),
            ]
          : [
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
            ],
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<String?> stop() async => startedPath;

  @override
  Future<void> cancel() async {}

  @override
  Stream<Uint8List> pcm16Chunks() => const Stream.empty();

  @override
  Stream<RecorderLevel> levels() => _levels.stream;

  @override
  Future<void> dispose() => _levels.close();
}
