import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/note_list_query.dart';
import '../application/notes_service.dart';
import '../application/smart_views_service.dart';
import '../application/tags_service.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import 'move_note.dart';
import 'providers.dart';
import 'theme.dart';

const _ruMonths = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

String dayLabel(DateTime local, DateTime now) {
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Сегодня';
  if (diff == 1) return 'Вчера';
  final base = '${day.day} ${_ruMonths[day.month - 1]}';
  return day.year == now.year ? base : '$base ${day.year}';
}

String timeLabel(DateTime local) =>
    '${local.hour}:${local.minute.toString().padLeft(2, '0')}';

/// Средняя панель: заголовок раздела, поиск, фильтр-чипы, список карточек.
class NotesListPane extends ConsumerStatefulWidget {
  final void Function(Note note) onOpenNote;

  /// Кнопка меню (Drawer) на узком макете.
  final bool showMenuButton;

  const NotesListPane({
    super.key,
    required this.onOpenNote,
    this.showMenuButton = false,
  });

  @override
  ConsumerState<NotesListPane> createState() => _NotesListPaneState();
}

class _NotesListPaneState extends ConsumerState<NotesListPane> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(searchQueryProvider.notifier).set(value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).set('');
  }

  Future<void> _runBulk(
    Future<void> Function(NotesService service, List<Note> notes) action,
  ) async {
    final ids = ref.read(bulkSelectedNoteIdsProvider);
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = await ref.read(notesServiceProvider.future);
      final notes = await service.getNotesByIds(ids);
      if (notes.length != ids.length) throw StateError('selection changed');
      await action(service, notes);
      ref.read(bulkSelectedNoteIdsProvider.notifier).clear();
      messenger.showSnackBar(
        SnackBar(content: Text('Изменено заметок: ${notes.length}')),
      );
    } on StateError {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Часть заметок изменилась — операция отменена целиком'),
        ),
      );
    } catch (error) {
      debugPrint('bulk note action failed: ${error.runtimeType}');
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось выполнить массовую операцию')),
      );
    }
  }

  Future<void> _bulkMove(List<Project> projects) async {
    const noProject = '__none__';
    final target = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Перенести выбранные'),
        children: [
          SimpleDialogOption(
            key: const ValueKey('bulk-project-none'),
            onPressed: () => Navigator.pop(dialogContext, noProject),
            child: const Text('Без проекта'),
          ),
          for (final project in projects)
            SimpleDialogOption(
              key: ValueKey('bulk-project-${project.id}'),
              onPressed: () => Navigator.pop(dialogContext, project.id),
              child: Text(project.name),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    await _runBulk(
      (service, notes) => service.bulkMoveToProject(
        notes,
        target == noProject ? null : target,
        resolution: ProjectTagResolution.drop,
      ),
    );
  }

  Future<void> _bulkTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Переместить выбранные в корзину?'),
        content: const Text('Операция выполняется атомарно для всего выбора.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('confirm-bulk-trash'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('В корзину'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runBulk((service, notes) => service.bulkMoveToTrash(notes));
    }
  }

  Future<void> _bulkAssignTag(List<Tag> tags) async {
    final tagId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Добавить тег выбранным'),
        children: [
          for (final tag in tags)
            SimpleDialogOption(
              key: ValueKey('bulk-tag-${tag.id}'),
              onPressed: () => Navigator.pop(dialogContext, tag.id),
              child: Text(tag.name),
            ),
        ],
      ),
    );
    if (tagId == null || !mounted) return;
    final ids = ref.read(bulkSelectedNoteIdsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final notesService = await ref.read(notesServiceProvider.future);
      final notes = await notesService.getNotesByIds(ids);
      if (notes.length != ids.length) throw StateError('selection changed');
      final tagsService = await ref.read(tagsServiceProvider.future);
      await tagsService.bulkAssignTag(notes, tagId);
      ref.read(bulkSelectedNoteIdsProvider.notifier).clear();
      messenger.showSnackBar(
        SnackBar(content: Text('Тег добавлен заметкам: ${notes.length}')),
      );
    } on StateError {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Заметки или тег изменились — операция отменена целиком',
          ),
        ),
      );
    } catch (error) {
      debugPrint('bulk tag failed: ${error.runtimeType}');
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось назначить тег')),
      );
    }
  }

  String _sectionTitle(NavSection section, List<Project> projects) {
    switch (section) {
      case AllNotesSection():
        return 'Все заметки';
      case NoProjectSection():
        return 'Без проекта';
      case FavoritesSection():
        return 'Избранное';
      case TrashSection():
        return 'Корзина';
      case ProjectSection(:final projectId):
        for (final p in projects) {
          if (p.id == projectId) return p.name;
        }
        return 'Проект';
      case SmartViewSection(:final name):
        return name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final section = ref.watch(navSectionProvider);
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    final projectId = switch (section) {
      ProjectSection(:final projectId) => projectId,
      _ => null,
    };
    final availableTags =
        ref.watch(availableTagsProvider(projectId)).value ?? const <Tag>[];
    final globalTags =
        ref.watch(availableTagsProvider(null)).value ?? const <Tag>[];
    final listSettings = ref.watch(noteListViewSettingsProvider);
    final selectedIds = ref.watch(bulkSelectedNoteIdsProvider);
    final isTrash = section is TrashSection;

    return Container(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (widget.showMenuButton)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: IconButton(
                          tooltip: 'Меню',
                          icon: Icon(Icons.menu_rounded, color: c.text),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        selectedIds.isEmpty
                            ? _sectionTitle(section, projects)
                            : 'Выбрано: ${selectedIds.length}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: c.text,
                        ),
                      ),
                    ),
                    if (selectedIds.isNotEmpty && !isTrash) ...[
                      IconButton(
                        key: const ValueKey('bulk-status-done'),
                        tooltip: 'Отметить выполненными',
                        onPressed: () => _runBulk(
                          (service, notes) =>
                              service.bulkSetStatus(notes, NoteStatus.done),
                        ),
                        icon: const Icon(Icons.done_all_rounded),
                      ),
                      IconButton(
                        key: const ValueKey('bulk-move'),
                        tooltip: 'Перенести в проект',
                        onPressed: () => _bulkMove(projects),
                        icon: const Icon(Icons.drive_file_move_outline),
                      ),
                      IconButton(
                        key: const ValueKey('bulk-tag'),
                        tooltip: 'Добавить глобальный тег',
                        onPressed: globalTags.isEmpty
                            ? null
                            : () => _bulkAssignTag(globalTags),
                        icon: const Icon(Icons.label_outline_rounded),
                      ),
                      IconButton(
                        key: const ValueKey('bulk-trash'),
                        tooltip: 'В корзину',
                        onPressed: _bulkTrash,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                      IconButton(
                        key: const ValueKey('bulk-clear'),
                        tooltip: 'Отменить выбор',
                        onPressed: () => ref
                            .read(bulkSelectedNoteIdsProvider.notifier)
                            .clear(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ] else if (!isTrash)
                      IconButton(
                        key: const ValueKey('note-list-settings'),
                        tooltip: 'Фильтры и сортировка',
                        onPressed: () => showNoteListSettingsSheet(
                          context,
                          ref,
                          section: section,
                          projects: projects,
                          tags: availableTags,
                        ),
                        icon: Badge(
                          isLabelVisible: listSettings.filter.isActive,
                          label: Text(
                            '${listSettings.filter.activeDimensionCount}',
                          ),
                          child: const Icon(Icons.tune_rounded),
                        ),
                      ),
                  ],
                ),
                if (!isTrash && selectedIds.isEmpty) ...[
                  const SizedBox(height: 14),
                  _SearchField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    onClear: _clearSearch,
                  ),
                  const SizedBox(height: 11),
                  const _FilterChipsRow(),
                ],
              ],
            ),
          ),
          Expanded(
            child: isTrash
                ? const _TrashList()
                : _NotesScroll(
                    onOpenNote: widget.onOpenNote,
                    enableDrag: MediaQuery.sizeOf(context).width >= 900,
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends ConsumerWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final query = ref.watch(searchQueryProvider);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(c.radiusSmall),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: c.muted),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: ref.watch(searchFocusProvider),
              onChanged: onChanged,
              style: TextStyle(fontSize: 13, color: c.text),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Поиск по заметкам',
                hintStyle: TextStyle(color: c.muted),
              ),
            ),
          ),
          if (query.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onClear,
              child: Icon(Icons.close_rounded, size: 16, color: c.muted),
            )
          else
            Text('Ctrl K', style: TextStyle(fontSize: 10, color: c.muted)),
        ],
      ),
    );
  }
}

class _FilterChipsRow extends ConsumerWidget {
  const _FilterChipsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final active = ref.watch(activeQuickFilterProvider);
    final settings = ref.watch(noteListViewSettingsProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in NoteChipFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => ref
                    .read(noteListViewSettingsProvider.notifier)
                    .selectQuick(filter),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: filter == active ? c.accentSoft : c.surface,
                    border: Border.all(
                      color: filter == active ? c.accent : c.line,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    filter.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: filter == active ? c.accent : c.muted,
                      fontWeight: filter == active
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          if (settings.filter.isActive)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: ActionChip(
                key: const ValueKey('clear-note-filters'),
                avatar: const Icon(Icons.close_rounded, size: 15),
                label: Text(
                  'Сбросить (${settings.filter.activeDimensionCount})',
                ),
                onPressed: () => ref
                    .read(noteListViewSettingsProvider.notifier)
                    .clearFilters(),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotesScroll extends ConsumerWidget {
  final void Function(Note note) onOpenNote;
  final bool enableDrag;

  const _NotesScroll({required this.onOpenNote, required this.enableDrag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final settings = ref.watch(noteListViewSettingsProvider);
    final query = ref.watch(searchQueryProvider).trim();
    final searching = query.isNotEmpty;

    final search = searching ? ref.watch(searchResultsProvider) : null;
    final page = searching ? null : ref.watch(visiblePagedNotesProvider);
    final notes = searching ? search?.value : page?.value?.notes;
    if (notes == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notes.isEmpty) {
      return Center(
        child: Text(
          searching || settings.filter.isActive
              ? 'Ничего не найдено'
              : 'Пока пусто — создайте первую заметку',
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
      );
    }

    final selectedId = ref.watch(selectedNoteIdProvider);
    final bulkSelectedIds = ref.watch(bulkSelectedNoteIdsProvider);
    final selectionMode = bulkSelectedIds.isNotEmpty;
    final now = DateTime.now();
    final children = <Widget>[];
    String? currentDay;
    for (final note in notes) {
      final groupAt = switch (settings.order.field) {
        NoteSortField.createdAt => note.createdAtUtc,
        NoteSortField.updatedAt => note.updatedAtUtc,
        NoteSortField.eventAt => note.eventAtUtc ?? note.createdAtUtc,
        NoteSortField.title || NoteSortField.project => null,
      };
      if (groupAt != null) {
        final label = dayLabel(
          DateTime.fromMillisecondsSinceEpoch(groupAt).toLocal(),
          now,
        );
        if (label != currentDay) {
          currentDay = label;
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 9, 5, 7),
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: c.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          );
        }
      }
      children.add(
        _NoteCard(
          note: note,
          selected: note.id == selectedId,
          bulkSelected: bulkSelectedIds.contains(note.id),
          onTap: () => selectionMode
              ? ref.read(bulkSelectedNoteIdsProvider.notifier).toggle(note.id)
              : onOpenNote(note),
          onToggleSelection: () =>
              ref.read(bulkSelectedNoteIdsProvider.notifier).toggle(note.id),
          onMove: () => showMoveNoteSheet(context, ref, note),
          enableDrag: enableDrag,
        ),
      );
    }

    if (!searching && page!.value!.loadingMore) {
      children.add(
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!searching &&
            notification.metrics.extentAfter < 600 &&
            page!.value!.hasMore) {
          unawaited(ref.read(pagedSectionNotesProvider.notifier).loadMore());
        }
        return false;
      },
      child: ListView(
        key: const ValueKey('paged-notes-list'),
        padding: const EdgeInsets.all(12),
        children: children,
      ),
    );
  }
}

class _NoteCard extends ConsumerWidget {
  final Note note;
  final bool selected;
  final bool bulkSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleSelection;
  final VoidCallback onMove;
  final bool enableDrag;

  const _NoteCard({
    required this.note,
    required this.selected,
    required this.bulkSelected,
    required this.onTap,
    required this.onToggleSelection,
    required this.onMove,
    required this.enableDrag,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final tags = ref.watch(noteTagsProvider(note.id)).value ?? const <Tag>[];
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    Project? project;
    for (final p in projects) {
      if (p.id == note.projectId) {
        project = p;
        break;
      }
    }

    // Полоса слева: цвет первого тега → цвет проекта → accent.
    final stripe = tags.isNotEmpty
        ? Color(tags.first.colorArgb)
        : project != null
        ? Color(project.colorArgb)
        : c.accent;

    final done = note.status == NoteStatus.done;
    final lines = note.documentPlainText
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList(growable: false);
    final title = lines.isEmpty ? 'Аудиозаметка' : lines.first;
    final preview = lines.length > 1 ? lines.skip(1).join(' ') : '';
    final order = ref.watch(noteListViewSettingsProvider).order;
    final displayedAt = switch (order.field) {
      NoteSortField.createdAt ||
      NoteSortField.title ||
      NoteSortField.project => note.createdAtUtc,
      NoteSortField.updatedAt => note.updatedAtUtc,
      NoteSortField.eventAt => note.eventAtUtc ?? note.createdAtUtc,
    };
    final displayedTime = DateTime.fromMillisecondsSinceEpoch(
      displayedAt,
    ).toLocal();

    Widget card = Material(
      color: selected || bulkSelected ? c.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(c.radiusSmall),
      child: InkWell(
        key: ValueKey('note-card-${note.id}'),
        borderRadius: BorderRadius.circular(c.radiusSmall),
        hoverColor: c.surface2,
        onTap: onTap,
        onLongPress: enableDrag ? null : onMove,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 11,
              bottom: 11,
              width: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: stripe,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 30,
                        height: 28,
                        child: Checkbox(
                          key: ValueKey('bulk-select-${note.id}'),
                          value: bulkSelected,
                          onChanged: (_) => onToggleSelection(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (tags.isNotEmpty) ...[
                        Flexible(
                          child: Text(
                            tags.first.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(tags.first.colorArgb),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                      ],
                      if (note.sourceKind == SourceKind.audio) ...[
                        Icon(Icons.mic_rounded, size: 11, color: c.muted),
                        const SizedBox(width: 4),
                      ],
                      if (project != null)
                        Flexible(
                          child: Text(
                            project.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: c.muted),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        timeLabel(displayedTime),
                        style: TextStyle(fontSize: 10, color: c.muted),
                      ),
                      const SizedBox(width: 2),
                      SizedBox.square(
                        dimension: 32,
                        child: IconButton(
                          key: ValueKey('move-note-${note.id}'),
                          tooltip: 'Перенести заметку',
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          color: c.muted,
                          onPressed: onMove,
                          icon: const Icon(Icons.drive_file_move_outline),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: c.text,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.42,
                        color: c.muted,
                      ),
                    ),
                  ],
                  if (tags.length > 1) ...[
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        for (final tag in tags.skip(1).take(3))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: c.surface3,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tag.name,
                              style: TextStyle(fontSize: 9, color: c.muted),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (done) {
      card = Opacity(opacity: 0.58, child: card);
    }
    final paddedCard = Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: card,
    );
    if (!enableDrag) return paddedCard;
    return LongPressDraggable<Note>(
      data: note,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        borderRadius: BorderRadius.circular(c.radiusSmall),
        child: SizedBox(width: 320, child: Opacity(opacity: 0.96, child: card)),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: paddedCard),
      child: paddedCard,
    );
  }
}

Future<void> showNoteListSettingsSheet(
  BuildContext context,
  WidgetRef ref, {
  required NavSection section,
  required List<Project> projects,
  required List<Tag> tags,
}) async {
  final current = ref.read(noteListViewSettingsProvider);
  var order = current.order;
  var includeNoProject = current.filter.includeNoProject;
  var tagMode = current.filter.tagMatchMode;
  var favoriteOnly = current.filter.favoriteOnly;
  var requireAudio = current.filter.requireAudio;
  var requireImage = current.filter.requireImage;
  var requireTranscript = current.filter.requireTranscript;
  var periodStart = current.filter.periodStartUtc;
  var periodEnd = current.filter.periodEndUtcExclusive;
  final projectIds = current.filter.projectIds.toSet();
  final tagIds = current.filter.tagIds.toSet();
  final statuses = current.filter.statuses.toSet();
  final showProjectFilter =
      section is AllNotesSection ||
      section is FavoritesSection ||
      section is SmartViewSection;

  NoteListFilter buildFilter() => NoteListFilter(
    projectIds: Set.unmodifiable(projectIds),
    includeNoProject: includeNoProject,
    tagIds: Set.unmodifiable(tagIds),
    tagMatchMode: tagMode,
    statuses: Set.unmodifiable(statuses),
    periodStartUtc: periodStart,
    periodEndUtcExclusive: periodEnd,
    favoriteOnly: favoriteOnly,
    requireAudio: requireAudio,
    requireImage: requireImage,
    requireTranscript: requireTranscript,
  );

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final periodText = periodStart == null || periodEnd == null
            ? 'Выбрать период'
            : '${_shortDate(periodStart!)} — '
                  '${_shortDate(periodEnd! - 1)}';
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Фильтры и сортировка',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<NoteSortField>(
                      key: const ValueKey('note-sort-field'),
                      initialValue: order.field,
                      decoration: const InputDecoration(
                        labelText: 'Сортировать по',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final field in NoteSortField.values)
                          DropdownMenuItem(
                            value: field,
                            child: Text(field.label),
                          ),
                      ],
                      onChanged: (field) {
                        if (field == null) return;
                        setSheetState(
                          () => order = order.copyWith(field: field),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<NoteSortDirection>(
                      segments: const [
                        ButtonSegment(
                          value: NoteSortDirection.descending,
                          label: Text('По убыванию'),
                          icon: Icon(Icons.arrow_downward_rounded),
                        ),
                        ButtonSegment(
                          value: NoteSortDirection.ascending,
                          label: Text('По возрастанию'),
                          icon: Icon(Icons.arrow_upward_rounded),
                        ),
                      ],
                      selected: {order.direction},
                      onSelectionChanged: (value) => setSheetState(
                        () => order = order.copyWith(direction: value.single),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Статус',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          key: const ValueKey('filter-status-in-work'),
                          label: const Text('В работе'),
                          selected: statuses.contains(NoteStatus.inWork),
                          onSelected: (selected) => setSheetState(() {
                            selected
                                ? statuses.add(NoteStatus.inWork)
                                : statuses.remove(NoteStatus.inWork);
                          }),
                        ),
                        FilterChip(
                          key: const ValueKey('filter-status-done'),
                          label: const Text('Выполнено'),
                          selected: statuses.contains(NoteStatus.done),
                          onSelected: (selected) => setSheetState(() {
                            selected
                                ? statuses.add(NoteStatus.done)
                                : statuses.remove(NoteStatus.done);
                          }),
                        ),
                      ],
                    ),
                    if (showProjectFilter && projects.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Проекты',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          FilterChip(
                            key: const ValueKey('filter-no-project'),
                            label: const Text('Без проекта'),
                            selected: includeNoProject,
                            onSelected: (selected) => setSheetState(
                              () => includeNoProject = selected,
                            ),
                          ),
                          for (final project in projects)
                            FilterChip(
                              key: ValueKey('filter-project-${project.id}'),
                              label: Text(project.name),
                              selected: projectIds.contains(project.id),
                              onSelected: (selected) => setSheetState(() {
                                selected
                                    ? projectIds.add(project.id)
                                    : projectIds.remove(project.id);
                              }),
                            ),
                        ],
                      ),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Теги',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          SegmentedButton<TagMatchMode>(
                            segments: const [
                              ButtonSegment(
                                value: TagMatchMode.any,
                                label: Text('Любой'),
                              ),
                              ButtonSegment(
                                value: TagMatchMode.all,
                                label: Text('Все'),
                              ),
                            ],
                            selected: {tagMode},
                            onSelectionChanged: (value) =>
                                setSheetState(() => tagMode = value.single),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final tag in tags)
                            FilterChip(
                              key: ValueKey('filter-tag-${tag.id}'),
                              avatar: CircleAvatar(
                                backgroundColor: Color(tag.colorArgb),
                              ),
                              label: Text(tag.name),
                              selected: tagIds.contains(tag.id),
                              onSelected: (selected) => setSheetState(() {
                                selected
                                    ? tagIds.add(tag.id)
                                    : tagIds.remove(tag.id);
                              }),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.date_range_rounded),
                            label: Text(periodText),
                            onPressed: () async {
                              final initial =
                                  periodStart == null || periodEnd == null
                                  ? null
                                  : DateTimeRange(
                                      start:
                                          DateTime.fromMillisecondsSinceEpoch(
                                            periodStart!,
                                            isUtc: true,
                                          ).toLocal(),
                                      end: DateTime.fromMillisecondsSinceEpoch(
                                        periodEnd! - 1,
                                        isUtc: true,
                                      ).toLocal(),
                                    );
                              final selected = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                                initialDateRange: initial,
                              );
                              if (selected == null || !context.mounted) return;
                              final start = DateTime(
                                selected.start.year,
                                selected.start.month,
                                selected.start.day,
                              );
                              final endExclusive = DateTime(
                                selected.end.year,
                                selected.end.month,
                                selected.end.day + 1,
                              );
                              setSheetState(() {
                                periodStart = start
                                    .toUtc()
                                    .millisecondsSinceEpoch;
                                periodEnd = endExclusive
                                    .toUtc()
                                    .millisecondsSinceEpoch;
                              });
                            },
                          ),
                        ),
                        if (periodStart != null || periodEnd != null)
                          IconButton(
                            tooltip: 'Сбросить период',
                            onPressed: () => setSheetState(() {
                              periodStart = null;
                              periodEnd = null;
                            }),
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                    SwitchListTile(
                      key: const ValueKey('filter-favorite'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Только избранные'),
                      value: favoriteOnly,
                      onChanged: (value) =>
                          setSheetState(() => favoriteOnly = value),
                    ),
                    SwitchListTile(
                      key: const ValueKey('filter-audio'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Есть аудио'),
                      value: requireAudio,
                      onChanged: (value) =>
                          setSheetState(() => requireAudio = value),
                    ),
                    SwitchListTile(
                      key: const ValueKey('filter-image'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Есть изображение'),
                      value: requireImage,
                      onChanged: (value) =>
                          setSheetState(() => requireImage = value),
                    ),
                    SwitchListTile(
                      key: const ValueKey('filter-transcript'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Есть расшифровка'),
                      value: requireTranscript,
                      onChanged: (value) =>
                          setSheetState(() => requireTranscript = value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton(
                          key: const ValueKey('save-smart-view'),
                          tooltip: 'Сохранить представление',
                          onPressed: () async {
                            final name = await _promptSmartViewName(context);
                            if (name == null || !context.mounted) return;
                            try {
                              final service = await ref.read(
                                smartViewsServiceProvider.future,
                              );
                              final id = await service.create(
                                name: name,
                                definition: SmartViewDefinition(
                                  filter: buildFilter(),
                                  order: order,
                                ),
                              );
                              ref
                                  .read(noteListViewSettingsProvider.notifier)
                                  .apply(filter: buildFilter(), order: order);
                              ref
                                  .read(navSectionProvider.notifier)
                                  .select(SmartViewSection(id, name.trim()));
                              if (context.mounted) Navigator.pop(context);
                            } catch (error) {
                              debugPrint(
                                'smart view save failed: '
                                '${error.runtimeType}',
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Не удалось сохранить представление',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.bookmark_add_outlined),
                        ),
                        TextButton(
                          onPressed: () {
                            ref
                                .read(noteListViewSettingsProvider.notifier)
                                .apply(
                                  filter: const NoteListFilter(),
                                  order: order,
                                );
                            Navigator.pop(context);
                          },
                          child: const Text('Сбросить фильтры'),
                        ),
                        const Spacer(),
                        FilledButton(
                          key: const ValueKey('apply-note-filters'),
                          onPressed: () {
                            ref
                                .read(noteListViewSettingsProvider.notifier)
                                .apply(filter: buildFilter(), order: order);
                            Navigator.pop(context);
                          },
                          child: const Text('Применить'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<String?> _promptSmartViewName(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Сохранить представление'),
      content: TextField(
        key: const ValueKey('smart-view-name'),
        controller: controller,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(
          labelText: 'Название',
          hintText: 'Например, открытые риски',
        ),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) Navigator.pop(dialogContext, value);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('confirm-smart-view'),
          onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(dialogContext, value);
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}

String _shortDate(int utcMillis) {
  final date = DateTime.fromMillisecondsSinceEpoch(
    utcMillis,
    isUtc: true,
  ).toLocal();
  return '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.${date.year}';
}

class _TrashList extends ConsumerWidget {
  const _TrashList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final page = ref.watch(visiblePagedNotesProvider).value;
    final trash = page?.notes;
    if (trash == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final loadedPage = page!;
    if (trash.isEmpty) {
      return Center(
        child: Text(
          'Корзина пуста',
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 600 && loadedPage.hasMore) {
          unawaited(ref.read(pagedSectionNotesProvider.notifier).loadMore());
        }
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('paged-trash-list'),
        padding: const EdgeInsets.all(12),
        itemCount: trash.length + (loadedPage.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == trash.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final note = trash[index];
          final lines = note.documentPlainText
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .toList(growable: false);
          final title = lines.isEmpty ? 'Аудиозаметка' : lines.first;
          final deletedAt = note.deletedAtUtc == null
              ? ''
              : dayLabel(
                  DateTime.fromMillisecondsSinceEpoch(
                    note.deletedAtUtc!,
                  ).toLocal(),
                  DateTime.now(),
                );
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(c.radiusSmall),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.text),
                      ),
                      if (deletedAt.isNotEmpty)
                        Text(
                          'Удалено: $deletedAt',
                          style: TextStyle(fontSize: 10, color: c.muted),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final service = await ref.read(
                        notesServiceProvider.future,
                      );
                      await service.restoreFromTrash(note);
                    } on StateError {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Заметка изменилась — список обновлён'),
                        ),
                      );
                    } catch (e) {
                      debugPrint('restore failed: ${e.runtimeType}');
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Не удалось восстановить заметку'),
                        ),
                      );
                    }
                  },
                  child: const Text('Восстановить'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
