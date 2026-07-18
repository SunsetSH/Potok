import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/presentation/providers.dart';
import 'package:potok/presentation/tag_management.dart';
import 'package:potok/presentation/theme.dart';

void main() {
  testWidgets('exposes create scope and edit controls for custom tags', (
    tester,
  ) async {
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
      scope: TagScope.project,
      projectId: 'project-1',
      name: 'Клиент',
      normalizedName: 'клиент',
      colorArgb: 0xFF2364C4,
      sortOrder: 0,
      createdAtUtc: 1,
      updatedAtUtc: 1,
      revision: 1,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider.overrideWith((ref) => Stream.value(const [project])),
          allTagsProvider.overrideWith((ref) => Stream.value(const [tag])),
        ],
        child: MaterialApp(
          theme: buildPotokTheme(PotokThemeId.studio),
          home: const Scaffold(
            body: SingleChildScrollView(child: TagManagementSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-custom-tag')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-scope')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-scope')));
    await tester.pumpAndSettle();
    expect(find.text('Глобальный · все заметки'), findsWidgets);
    expect(find.text('Проект · Проект Альфа'), findsWidgets);
    await tester.tap(find.text('Глобальный · все заметки').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('manage-tag-tag-1')), findsOneWidget);
    await tester.tap(find.byTooltip('Редактировать тег'));
    await tester.pumpAndSettle();
    expect(find.text('Редактировать тег'), findsOneWidget);
    expect(find.text('Тег проекта · область не изменяется'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('tag-name')))
          .controller!
          .text,
      'Клиент',
    );
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
  });
}
