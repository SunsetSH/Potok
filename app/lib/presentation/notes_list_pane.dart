import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../infrastructure/db/database.dart';
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final section = ref.watch(navSectionProvider);
    final projects =
        ref.watch(projectsProvider).value ?? const <Project>[];
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
                        _sectionTitle(section, projects),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: c.text,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!isTrash) ...[
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
                : _NotesScroll(onOpenNote: widget.onOpenNote),
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
    final active = ref.watch(chipFilterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in NoteChipFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () =>
                    ref.read(chipFilterProvider.notifier).select(filter),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                      fontWeight:
                          filter == active ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

bool _matchesSection(Note note, NavSection section) => switch (section) {
      AllNotesSection() => true,
      NoProjectSection() => note.projectId == null,
      FavoritesSection() => note.isFavorite,
      ProjectSection(:final projectId) => note.projectId == projectId,
      TrashSection() => false,
    };

bool _matchesChip(Note note, NoteChipFilter filter) => switch (filter) {
      NoteChipFilter.all => true,
      NoteChipFilter.inWork => note.status == NoteStatus.inWork,
      NoteChipFilter.done => note.status == NoteStatus.done,
      NoteChipFilter.withAudio => note.sourceKind == SourceKind.audio,
    };

class _NotesScroll extends ConsumerWidget {
  final void Function(Note note) onOpenNote;

  const _NotesScroll({required this.onOpenNote});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final section = ref.watch(navSectionProvider);
    final chip = ref.watch(chipFilterProvider);
    final query = ref.watch(searchQueryProvider).trim();
    final searching = query.isNotEmpty;

    final asyncNotes =
        searching ? ref.watch(searchResultsProvider) : ref.watch(sectionNotesProvider);
    final raw = asyncNotes.value;
    if (raw == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final notes = raw
        .where((n) => _matchesChip(n, chip))
        .where((n) => !searching || _matchesSection(n, section))
        .toList(growable: false);

    if (notes.isEmpty) {
      return Center(
        child: Text(
          searching || chip != NoteChipFilter.all
              ? 'Ничего не найдено'
              : 'Пока пусто — создайте первую заметку',
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
      );
    }

    final selectedId = ref.watch(selectedNoteIdProvider);
    final now = DateTime.now();
    final children = <Widget>[];
    String? currentDay;
    for (final note in notes) {
      final label = dayLabel(
          DateTime.fromMillisecondsSinceEpoch(note.createdAtUtc).toLocal(),
          now);
      if (label != currentDay) {
        currentDay = label;
        children.add(Padding(
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
        ));
      }
      children.add(_NoteCard(
        note: note,
        selected: note.id == selectedId,
        onTap: () => onOpenNote(note),
      ));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: children,
    );
  }
}

class _NoteCard extends ConsumerWidget {
  final Note note;
  final bool selected;
  final VoidCallback onTap;

  const _NoteCard({
    required this.note,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final tags = ref.watch(noteTagsProvider(note.id)).value ??
        const <Tag>[];
    final projects =
        ref.watch(projectsProvider).value ?? const <Project>[];
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
    final created =
        DateTime.fromMillisecondsSinceEpoch(note.createdAtUtc).toLocal();

    Widget card = Material(
      color: selected ? c.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(c.radiusSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(c.radiusSmall),
        hoverColor: c.surface2,
        onTap: onTap,
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
                        timeLabel(created),
                        style: TextStyle(fontSize: 10, color: c.muted),
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
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: c.surface3,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tag.name,
                              style:
                                  TextStyle(fontSize: 9, color: c.muted),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: card,
    );
  }
}

class _TrashList extends ConsumerWidget {
  const _TrashList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final trash = ref.watch(trashNotesProvider).value;
    if (trash == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (trash.isEmpty) {
      return Center(
        child: Text('Корзина пуста',
            style: TextStyle(color: c.muted, fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: trash.length,
      itemBuilder: (context, index) {
        final note = trash[index];
        final lines = note.documentPlainText
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList(growable: false);
        final title = lines.isEmpty ? 'Аудиозаметка' : lines.first;
        final deletedAt = note.deletedAtUtc == null
            ? ''
            : dayLabel(
                DateTime.fromMillisecondsSinceEpoch(note.deletedAtUtc!)
                    .toLocal(),
                DateTime.now());
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
                    final service =
                        await ref.read(notesServiceProvider.future);
                    await service.restoreFromTrash(note);
                  } on StateError {
                    messenger.showSnackBar(const SnackBar(
                        content:
                            Text('Заметка изменилась — список обновлён')));
                  } catch (e) {
                    debugPrint('restore failed: ${e.runtimeType}');
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Не удалось восстановить заметку')));
                  }
                },
                child: const Text('Восстановить'),
              ),
            ],
          ),
        );
      },
    );
  }
}
