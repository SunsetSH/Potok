import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';
import 'package:potok/presentation/notes_list_pane.dart';
import 'package:potok/presentation/providers.dart';
import 'package:potok/presentation/theme.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late NotesService service;
  late Note note;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_card_actions_test');
    service = NotesService(
      db: db,
      media: MediaStore(temp),
      clock: FixedClock(DateTime.utc(2026, 7, 18, 12)),
      ids: SequentialIdGenerator(),
      deviceId: 'device-test',
    );
    final id = await service.createTextNote('Быстрое действие');
    note = (await service.getNote(id))!;
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      notesServiceProvider.overrideWithValue(AsyncData(service)),
      visiblePagedNotesProvider.overrideWith(
        (ref) => AsyncData(
          PagedNotesState(notes: [note], nextCursor: null, hasMore: false),
        ),
      ),
      projectsProvider.overrideWith((ref) => Stream.value(const [])),
      noteTagsProvider.overrideWith((ref, id) => Stream.value(const [])),
      availableTagsProvider.overrideWith((ref, id) => Stream.value(const [])),
    ],
    child: MaterialApp(
      theme: buildPotokTheme(PotokThemeId.studio),
      home: Scaffold(body: NotesListPane(onOpenNote: (_) {})),
    ),
  );

  testWidgets('card exposes and executes favorite action', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final action = find.byKey(ValueKey('favorite-note-${note.id}'));
    expect(action, findsOneWidget);
    expect(find.byKey(ValueKey('done-note-${note.id}')), findsOneWidget);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();

    expect((await service.getNote(note.id))!.isFavorite, isTrue);
  });

  testWidgets('card executes done action', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final action = find.byKey(ValueKey('done-note-${note.id}'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();

    expect((await service.getNote(note.id))!.status, NoteStatus.done);
  });
}
