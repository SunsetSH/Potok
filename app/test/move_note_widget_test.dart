import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/note_list_query.dart';
import 'package:potok/domain/document.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/presentation/notes_list_pane.dart';
import 'package:potok/presentation/providers.dart';
import 'package:potok/presentation/sidebar.dart';
import 'package:potok/presentation/theme.dart';

void main() {
  const project = Project(
    id: 'project-1',
    name: 'Мобильный банк',
    description: '',
    colorArgb: 0xFF4E75DB,
    isPinned: false,
    isArchived: false,
    createdAtUtc: 1,
    updatedAtUtc: 1,
    revision: 1,
  );
  final note = Note(
    id: 'note-1',
    documentJson: PotokDocument.fromPlainText('Проверить перевод').encode(),
    documentPlainText: 'Проверить перевод',
    status: NoteStatus.inWork,
    sourceKind: SourceKind.keyboard,
    isPinned: false,
    isFavorite: false,
    isHidden: false,
    createdAtUtc: 1,
    updatedAtUtc: 1,
    revision: 1,
  );

  Widget app({
    required Size size,
    required Widget child,
    List<Project> projects = const [project],
  }) {
    return ProviderScope(
      overrides: [
        visiblePagedNotesProvider.overrideWith(
          (ref) => AsyncData(
            PagedNotesState(notes: [note], nextCursor: null, hasMore: false),
          ),
        ),
        navigationSummaryProvider.overrideWith(
          (ref) => Stream.value(
            const NavigationSummary(
              total: 1,
              noProject: 1,
              favorites: 0,
              trash: 0,
            ),
          ),
        ),
        projectNoteCountsProvider.overrideWith(
          (ref) => Stream.value(const <String, int>{}),
        ),
        projectsProvider.overrideWith((ref) => Stream.value(projects)),
        smartViewsProvider.overrideWith((ref) => Stream.value(const [])),
        availableTagsProvider.overrideWith(
          (ref, projectId) => Stream.value(const []),
        ),
        noteTagsProvider.overrideWith((ref, noteId) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: buildPotokTheme(PotokThemeId.studio),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  testWidgets('narrow card long press opens scrollable 56dp project tray', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        size: const Size(600, 800),
        child: NotesListPane(onOpenNote: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('note-card-note-1')));
    await tester.pumpAndSettle();

    expect(find.text('Перенести в проект'), findsOneWidget);
    final noProject = find.byKey(const ValueKey('move-target-none'));
    final targetProject = find.byKey(const ValueKey('move-target-project-1'));
    expect(noProject, findsOneWidget);
    expect(targetProject, findsOneWidget);
    expect(tester.getSize(noProject).height, greaterThanOrEqualTo(56));
    expect(tester.getSize(targetProject).height, greaterThanOrEqualTo(56));
  });

  testWidgets('card exposes button equivalent for move tray', (tester) async {
    await tester.pumpWidget(
      app(
        size: const Size(600, 800),
        child: NotesListPane(onOpenNote: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('move-note-note-1')));
    await tester.pumpAndSettle();

    expect(find.text('Перенести в проект'), findsOneWidget);
  });

  testWidgets('checkbox enters and exits bounded bulk selection mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        size: const Size(1000, 800),
        child: NotesListPane(onOpenNote: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bulk-select-note-1')));
    await tester.pump();
    expect(find.text('Выбрано: 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-status-done')), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-move')), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-trash')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bulk-clear')));
    await tester.pump();
    expect(find.text('Выбрано: 1'), findsNothing);
  });

  testWidgets('wide layout exposes draggable cards and project drop targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        size: const Size(1200, 800),
        child: Row(
          children: [
            const Sidebar(),
            SizedBox(width: 400, child: NotesListPane(onOpenNote: (_) {})),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Draggable<Note>), findsOneWidget);
    final targetFinder = find.byKey(const ValueKey('project-drop-project-1'));
    expect(targetFinder, findsOneWidget);
    final target = tester.widget<DragTarget<Note>>(targetFinder);
    expect(
      target.onWillAcceptWithDetails!(
        DragTargetDetails(data: note, offset: Offset.zero),
      ),
      isTrue,
    );
    expect(
      target.onWillAcceptWithDetails!(
        DragTargetDetails(
          data: note.copyWith(projectId: const Value('project-1')),
          offset: Offset.zero,
        ),
      ),
      isFalse,
    );
  });

  testWidgets('drag near project-list edge advances controlled autoscroll', (
    tester,
  ) async {
    final projects = List.generate(
      30,
      (index) => Project(
        id: 'project-$index',
        name: 'Проект $index',
        description: '',
        colorArgb: 0xFF4E75DB,
        isPinned: false,
        isArchived: false,
        createdAtUtc: index,
        updatedAtUtc: index,
        revision: 1,
      ),
    );
    await tester.pumpWidget(
      app(
        size: const Size(1200, 500),
        projects: projects,
        child: const Sidebar(),
      ),
    );
    await tester.pumpAndSettle();

    final targetFinder = find.byKey(const ValueKey('project-drop-project-0'));
    final target = tester.widget<DragTarget<Note>>(targetFinder);
    final scrollableFinder = find
        .descendant(of: find.byType(Sidebar), matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollableFinder).position;
    final rect = tester.getRect(scrollableFinder);
    expect(position.pixels, 0);
    expect(position.maxScrollExtent, greaterThan(0));

    for (var index = 0; index < 20; index++) {
      target.onMove!(
        DragTargetDetails(
          data: note,
          offset: Offset(rect.center.dx, rect.bottom - 2),
        ),
      );
    }

    expect(position.pixels, greaterThan(0));
  });
}
