import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/note_list_query.dart';
import 'package:potok/application/smart_views_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/presentation/notes_list_pane.dart';
import 'package:potok/presentation/providers.dart';
import 'package:potok/presentation/theme.dart';

void main() {
  const project = Project(
    id: 'project-1',
    name: 'Проект Альфа',
    description: '',
    colorArgb: 0xFF4E75DB,
    isPinned: false,
    isArchived: false,
    createdAtUtc: 1,
    updatedAtUtc: 1,
    revision: 1,
  );
  const tag = Tag(
    id: 'tag-1',
    scope: TagScope.global,
    name: 'Риск',
    normalizedName: 'риск',
    colorArgb: 0xFFB85C16,
    sortOrder: 0,
    createdAtUtc: 1,
    updatedAtUtc: 1,
    revision: 1,
  );

  Widget app() => ProviderScope(
    overrides: [
      visiblePagedNotesProvider.overrideWith(
        (ref) => const AsyncData(
          PagedNotesState(notes: [], nextCursor: null, hasMore: false),
        ),
      ),
      projectsProvider.overrideWith((ref) => Stream.value(const [project])),
      availableTagsProvider.overrideWith(
        (ref, projectId) => Stream.value(const [tag]),
      ),
    ],
    child: MaterialApp(
      theme: buildPotokTheme(PotokThemeId.studio),
      home: Scaffold(body: NotesListPane(onOpenNote: (_) {})),
    ),
  );

  testWidgets('advanced settings apply combined filters and list order', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotesListPane)),
    );
    await tester.tap(find.byKey(const ValueKey('note-list-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-sort-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменено').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('По возрастанию'));

    for (final key in const [
      ValueKey('filter-status-in-work'),
      ValueKey('filter-project-project-1'),
      ValueKey('filter-tag-tag-1'),
      ValueKey('filter-audio'),
      ValueKey('filter-image'),
      ValueKey('filter-transcript'),
    ]) {
      final target = find.byKey(key);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
    }

    final apply = find.byKey(const ValueKey('apply-note-filters'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    final state = container.read(noteListViewSettingsProvider);
    expect(state.order.field, NoteSortField.updatedAt);
    expect(state.order.direction, NoteSortDirection.ascending);
    expect(state.filter.statuses, {NoteStatus.inWork});
    expect(state.filter.projectIds, {'project-1'});
    expect(state.filter.tagIds, {'tag-1'});
    expect(state.filter.requireAudio, isTrue);
    expect(state.filter.requireImage, isTrue);
    expect(state.filter.requireTranscript, isTrue);
    expect(state.filter.activeDimensionCount, 6);
    expect(find.byKey(const ValueKey('clear-note-filters')), findsOneWidget);
  });

  testWidgets('quick status chip preserves unrelated advanced filters', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotesListPane)),
    );
    container
        .read(noteListViewSettingsProvider.notifier)
        .apply(
          filter: const NoteListFilter(tagIds: {'tag-1'}, requireImage: true),
          order: const NoteListOrder(field: NoteSortField.title),
        );
    await tester.pump();

    await tester.tap(find.text('Выполнено').first);
    await tester.pump();

    final state = container.read(noteListViewSettingsProvider);
    expect(state.filter.statuses, {NoteStatus.done});
    expect(state.filter.tagIds, {'tag-1'});
    expect(state.filter.requireImage, isTrue);
    expect(state.order.field, NoteSortField.title);
  });

  testWidgets('clear action remains fully visible on a narrow list pane', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotesListPane)),
    );
    container
        .read(noteListViewSettingsProvider.notifier)
        .apply(
          filter: const NoteListFilter(requireAudio: true),
          order: const NoteListOrder(),
        );
    await tester.pump();

    final clear = find.byKey(const ValueKey('clear-note-filters'));
    expect(clear, findsOneWidget);
    final rect = tester.getRect(clear);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(390));
    final filters = tester.getRect(
      find.byKey(const ValueKey('note-filter-scroll')),
    );
    expect(rect.bottom, lessThanOrEqualTo(filters.top));
  });

  testWidgets('current filter can be named and saved as a smart view', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = SmartViewsService(
      db: db,
      clock: FixedClock(DateTime.utc(2026, 7, 17)),
      ids: SequentialIdGenerator(),
      deviceId: 'device-test',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          visiblePagedNotesProvider.overrideWith(
            (ref) => const AsyncData(
              PagedNotesState(notes: [], nextCursor: null, hasMore: false),
            ),
          ),
          projectsProvider.overrideWith((ref) => Stream.value(const [project])),
          availableTagsProvider.overrideWith(
            (ref, projectId) => Stream.value(const [tag]),
          ),
          smartViewsServiceProvider.overrideWith((ref) => service),
        ],
        child: MaterialApp(
          theme: buildPotokTheme(PotokThemeId.studio),
          home: Scaffold(body: NotesListPane(onOpenNote: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotesListPane)),
    );

    await tester.tap(find.byKey(const ValueKey('note-list-settings')));
    await tester.pumpAndSettle();
    final image = find.byKey(const ValueKey('filter-image'));
    await tester.ensureVisible(image);
    await tester.tap(image);
    final save = find.byKey(const ValueKey('save-smart-view'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('smart-view-name')),
      'С изображениями',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-smart-view')));
    await tester.pump(const Duration(seconds: 1));

    final views = await db.select(db.smartViews).get();
    expect(views.single.name, 'С изображениями');
    expect(service.definitionOf(views.single).filter.requireImage, isTrue);
    expect(container.read(navSectionProvider), isA<SmartViewSection>());
    expect(
      container.read(noteListViewSettingsProvider).filter.requireImage,
      isTrue,
    );
  });
}
