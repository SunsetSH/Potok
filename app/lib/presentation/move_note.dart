import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/note_list_query.dart';
import '../application/tags_service.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import 'providers.dart';
import 'theme.dart';

/// Перенос заметки в проект (FR-MOV-001..005): проверка конфликта
/// project-тегов с явным выбором их судьбы, сам перенос и SnackBar
/// с отменой. Общий сценарий для drag&drop, bottom sheet и меню.
Future<void> moveNoteToProject(
  BuildContext context,
  WidgetRef ref,
  Note note,
  String? targetProjectId,
) async {
  if (note.projectId == targetProjectId) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final tagsService = await ref.read(tagsServiceProvider.future);
    final tags = await tagsService.watchNoteTags(note.id).first;
    final conflicting = tags
        .where(
          (t) => t.scope == TagScope.project && t.projectId != targetProjectId,
        )
        .toList(growable: false);

    var resolution = ProjectTagResolution.drop;
    if (conflicting.isNotEmpty) {
      if (!context.mounted) return;
      final chosen = await _askProjectTagResolution(context, conflicting);
      if (chosen == null) return; // Отмена
      resolution = chosen;
    }

    final notesService = await ref.read(notesServiceProvider.future);
    await notesService.moveToProject(
      note,
      targetProjectId,
      resolution: resolution,
    );
    ref.invalidate(pagedSectionNotesProvider);
    ref.invalidate(searchResultsProvider);

    final projects = ref.read(projectsProvider).value ?? const <Project>[];
    String targetName = 'Без проекта';
    for (final p in projects) {
      if (p.id == targetProjectId) {
        targetName = p.name;
        break;
      }
    }
    final previousProjectId = note.projectId;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Перенесено в «$targetName»'),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () =>
              _undoMove(ref, messenger, note.id, previousProjectId),
        ),
      ),
    );
  } on StateError {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Заметка изменилась — показана актуальная версия'),
      ),
    );
  } catch (e) {
    debugPrint('move note failed: ${e.runtimeType}');
    messenger.showSnackBar(
      const SnackBar(content: Text('Не удалось перенести заметку')),
    );
  }
}

/// Undo: обратный перенос по свежей ревизии заметки (после переноса
/// revision изменился, старый снимок непригоден).
Future<void> _undoMove(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  String noteId,
  String? previousProjectId,
) async {
  try {
    final notesService = await ref.read(notesServiceProvider.future);
    final fresh = await notesService.getNote(noteId);
    if (fresh == null) return; // заметка удалена — отменять нечего
    await notesService.moveToProject(fresh, previousProjectId);
    ref.invalidate(pagedSectionNotesProvider);
    ref.invalidate(searchResultsProvider);
  } catch (e) {
    debugPrint('undo move failed: ${e.runtimeType}');
    messenger.showSnackBar(
      const SnackBar(content: Text('Не удалось отменить перенос')),
    );
  }
}

/// Судьба project-тегов прежнего проекта показывается явно (ТЗ 0.5.2).
Future<ProjectTagResolution?> _askProjectTagResolution(
  BuildContext context,
  List<Tag> conflicting,
) {
  final names = conflicting.map((t) => '«${t.name}»').join(', ');
  return showDialog<ProjectTagResolution>(
    context: context,
    builder: (dialogContext) {
      final c = PotokColors.of(dialogContext);
      return AlertDialog(
        title: const Text('Теги проекта'),
        content: Text(
          'У заметки есть теги прежнего проекта: $names. '
          'Что с ними сделать при переносе?',
          style: TextStyle(fontSize: 13, color: c.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(ProjectTagResolution.convertToGlobal),
            child: const Text('Сделать глобальными'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ProjectTagResolution.drop),
            child: const Text('Удалить теги проекта'),
          ),
        ],
      );
    },
  );
}

/// Узкий макет / Android: modal bottom sheet выбора проекта
/// (элементы min height 56 — FR-MOV-004).
Future<void> showMoveNoteSheet(BuildContext context, WidgetRef ref, Note note) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Consumer(
        builder: (sheetContext, sheetRef, _) {
          final c = PotokColors.of(sheetContext);
          final projects =
              sheetRef.watch(projectsProvider).value ?? const <Project>[];
          final summary =
              sheetRef.watch(navigationSummaryProvider).value ??
              NavigationSummary.empty;
          final byProject =
              sheetRef.watch(projectNoteCountsProvider).value ??
              const <String, int>{};

          Widget item({
            required Widget leading,
            required String label,
            required int count,
            required String? targetProjectId,
          }) {
            final current = note.projectId == targetProjectId;
            return InkWell(
              key: ValueKey('move-target-${targetProjectId ?? 'none'}'),
              onTap: current
                  ? null
                  : () {
                      Navigator.of(sheetContext).pop();
                      moveNoteToProject(context, ref, note, targetProjectId);
                    },
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    SizedBox(width: 22, child: leading),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: current ? c.muted : c.text,
                          fontWeight: current
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (current)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          'текущий',
                          style: TextStyle(fontSize: 11, color: c.muted),
                        ),
                      ),
                    Text(
                      '$count',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
            );
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Text(
                      'Перенести в проект',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        item(
                          leading: Icon(
                            Icons.crop_square_rounded,
                            size: 16,
                            color: c.muted,
                          ),
                          label: 'Без проекта',
                          count: summary.noProject,
                          targetProjectId: null,
                        ),
                        for (final project in projects)
                          item(
                            leading: Icon(
                              Icons.circle,
                              size: 12,
                              color: Color(project.colorArgb),
                            ),
                            label: project.name,
                            count: byProject[project.id] ?? 0,
                            targetProjectId: project.id,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
