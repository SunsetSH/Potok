import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/clipboard_image_reader.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/document.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/audio_player_controller.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';
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
    temp = await Directory.systemTemp.createTemp('potok_detail_widget_test');
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

  Widget detail(
    Note selected, {
    MediaAsset? audioAsset,
    AudioPlaybackController Function()? playerFactory,
    ClipboardImageReader? clipboardReader,
    NotesService? service,
  }) => ProviderScope(
    overrides: [
      notesServiceProvider.overrideWithValue(AsyncData(service ?? notes)),
      selectedNoteProvider.overrideWith((ref) => selected),
      projectsProvider.overrideWith((ref) => Stream.value(const [])),
      noteTagsProvider.overrideWith((ref, id) => Stream.value(const [])),
      availableTagsProvider.overrideWith((ref, id) => Stream.value(const [])),
      audioAssetsProvider.overrideWith(
        (ref, id) => Stream.value(
          audioAsset == null ? const <MediaAsset>[] : [audioAsset],
        ),
      ),
      revisionsProvider.overrideWith((ref, id) => Stream.value(const [])),
      mediaStoreProvider.overrideWithValue(AsyncData(MediaStore(temp))),
      if (clipboardReader != null)
        clipboardImageReaderProvider.overrideWithValue(clipboardReader),
      if (playerFactory != null)
        audioPlaybackControllerFactoryProvider.overrideWithValue(playerFactory),
    ],
    child: MaterialApp(
      theme: buildPotokTheme(PotokThemeId.studio),
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('ru'), Locale('en')],
      home: const Scaffold(body: NoteDetailPane()),
    ),
  );

  testWidgets('rich local edit and checklist are saved in one revision', (
    tester,
  ) async {
    await tester.pumpWidget(detail(note));
    await tester.pumpAndSettle();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    final controller = editor.controller;

    controller.replaceText(
      0,
      0,
      'Важно: ',
      const TextSelection.collapsed(offset: 7),
    );
    controller.formatText(0, 6, Attribute.bold);
    controller.formatText(0, controller.document.length, Attribute.unchecked);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();

    final saved = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(note.id))).getSingle();
    final document = PotokDocument.decode(saved.documentJson);
    expect(saved.revision, note.revision + 1);
    expect(saved.documentPlainText, startsWith('Важно: Проверить сценарий'));
    expect(
      document.deltaOps,
      contains(
        predicate<Map<String, Object?>>((op) {
          final attributes = op['attributes'];
          return attributes is Map<String, Object?> &&
              attributes['list'] == 'unchecked';
        }),
      ),
    );
    expect(
      document.deltaOps,
      contains(
        predicate<Map<String, Object?>>((op) {
          final attributes = op['attributes'];
          return attributes is Map<String, Object?> &&
              attributes['bold'] == true;
        }),
      ),
    );
  });

  testWidgets('dispose flushes edits made during an in-flight autosave', (
    tester,
  ) async {
    final gated = _GatedNotesService(
      db: db,
      media: MediaStore(temp),
      clock: FixedClock(DateTime.utc(2026, 7, 17, 12)),
      ids: SequentialIdGenerator(),
      deviceId: 'device-test',
    );
    await tester.pumpWidget(detail(note, service: gated));
    await tester.pumpAndSettle();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    final controller = editor.controller;

    // Первая правка: автосохранение стартует и виснет на gate.
    gated.gate = Completer<void>();
    controller.replaceText(
      0,
      0,
      'Первая. ',
      const TextSelection.collapsed(offset: 8),
    );
    await tester.pump(const Duration(milliseconds: 550));
    expect(gated.updateCalls, 1);

    // Вторая правка приходит, пока первое сохранение ещё в полёте.
    controller.replaceText(
      8,
      0,
      'Вторая. ',
      const TextSelection.collapsed(offset: 16),
    );

    // Панель закрывается до завершения первого сохранения.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    gated.gate!.complete();
    await tester.pumpAndSettle();

    // Финальный flush сериализован после in-flight: обе правки durable,
    // вторая запись идёт с актуальной ревизией (без тихого StateError).
    final saved = await (db.select(
      db.notes,
    )..where((row) => row.id.equals(note.id))).getSingle();
    expect(gated.updateCalls, 2);
    expect(saved.revision, note.revision + 2);
    expect(
      saved.documentPlainText,
      startsWith('Первая. Вторая. Проверить сценарий'),
    );
  });

  testWidgets('malformed canonical document degrades to empty editor', (
    tester,
  ) async {
    final malformed = note.copyWith(documentJson: '{broken');

    await tester.pumpWidget(detail(malformed));
    await tester.pumpAndSettle();

    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText(), '\n');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+V delegates paste to the clipboard image adapter', (
    tester,
  ) async {
    final clipboard = _FakeClipboardImageReader();
    await tester.pumpWidget(detail(note, clipboardReader: clipboard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(QuillEditor));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(clipboard.reads, 1);
  });

  testWidgets('audio controls expose play, seek and allowlisted speed', (
    tester,
  ) async {
    final fake = _FakeAudioPlaybackController();
    final audioNote = note.copyWith(sourceKind: SourceKind.audio);
    final asset = MediaAsset(
      id: 'audio-1',
      ownerNoteId: note.id,
      kind: AssetKind.audio,
      relativePath: 'au/audio-1.m4a',
      mimeType: 'audio/mp4',
      sizeBytes: 1024,
      sha256: 'hash',
      lifecycleState: AssetLifecycle.ready,
      createdAtUtc: 1,
      updatedAtUtc: 1,
    );

    await tester.pumpWidget(
      detail(audioNote, audioAsset: asset, playerFactory: () => fake),
    );
    await tester.pumpAndSettle();

    expect(fake.openedPath!.replaceAll('\\', '/'), endsWith('/au/audio-1.m4a'));
    await tester.tap(find.byKey(const ValueKey('audio-play-audio-1')));
    expect(fake.state.playing, isTrue);
    await tester.tap(find.byKey(const ValueKey('audio-forward-audio-1')));
    expect(fake.state.position, const Duration(seconds: 10));

    await tester.tap(find.byKey(const ValueKey('audio-speed-audio-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5×').last);
    await tester.pump();
    expect(fake.state.speed, 1.5);
    await tester.tap(find.byKey(const ValueKey('audio-manual-audio-1')));
    await tester.pump();
    expect(fake.state.playing, isFalse);
    final progress = find.byKey(const ValueKey('audio-progress-audio-1'));
    expect(progress, findsOneWidget);
    await fake.seek(const Duration(seconds: 25));
    await tester.pump();
    expect(tester.widget<Slider>(progress).value, 25000);
    expect(tester.widget<Slider>(progress).max, 60000);
    expect(
      find.ancestor(of: progress, matching: find.byType(Semantics)),
      findsWidgets,
    );
  });
}

/// NotesService, у которого updateDocument можно подвесить на Completer —
/// моделирует медленную запись для проверки гонки dispose ↔ автосохранение.
class _GatedNotesService extends NotesService {
  _GatedNotesService({
    required super.db,
    required super.media,
    required super.clock,
    required super.ids,
    required super.deviceId,
  });

  Completer<void>? gate;
  int updateCalls = 0;

  @override
  Future<void> updateDocument(Note note, PotokDocument document) async {
    updateCalls++;
    final pending = gate;
    if (pending != null) await pending.future;
    return super.updateDocument(note, document);
  }
}

class _FakeClipboardImageReader implements ClipboardImageReader {
  int reads = 0;

  @override
  Future<ClipboardImage?> readImage() async {
    reads++;
    return null;
  }
}

class _FakeAudioPlaybackController extends AudioPlaybackController {
  AudioPlaybackState _state = const AudioPlaybackState(
    loading: false,
    duration: Duration(minutes: 1),
  );
  String? openedPath;

  @override
  AudioPlaybackState get state => _state;

  @override
  Future<void> open(String path) async => openedPath = path;

  @override
  Future<void> seek(Duration position) async {
    _state = _state.copyWith(position: position);
    notifyListeners();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _state = _state.copyWith(speed: speed);
    notifyListeners();
  }

  @override
  Future<void> skip(Duration delta) => seek(_state.position + delta);

  @override
  Future<void> toggle() async {
    _state = _state.copyWith(playing: !_state.playing);
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _state = _state.copyWith(playing: false);
    notifyListeners();
  }
}
