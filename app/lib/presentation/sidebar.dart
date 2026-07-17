import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/note_list_query.dart';
import '../application/notes_service.dart';
import '../application/settings_service.dart';
import '../infrastructure/asr/model_manager.dart';
import '../infrastructure/db/database.dart';
import 'move_note.dart';
import 'providers.dart';
import 'session_history.dart';
import 'theme.dart';

/// Предустановленные цвета проектов (диалог «+ проект»).
const projectPresetColors = <int>[
  0xFF4E75DB,
  0xFF8C65C5,
  0xFFD07B36,
  0xFF23825E,
  0xFFC53C4B,
  0xFF2364C4,
  0xFF1E8A8A,
  0xFFAD7A00,
  0xFF64707F,
  0xFF7656BD,
];

/// Левая панель: бренд, навигация, проекты, корзина и настройки.
class Sidebar extends ConsumerStatefulWidget {
  /// Закрывает Drawer на узком макете после выбора раздела.
  final VoidCallback? onNavigate;

  const Sidebar({super.key, this.onNavigate});

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  final _projectsScroll = ScrollController();
  final _projectsListKey = GlobalKey();

  @override
  void dispose() {
    _projectsScroll.dispose();
    super.dispose();
  }

  void _select(WidgetRef ref, NavSection section) {
    ref.read(navSectionProvider.notifier).select(section);
    widget.onNavigate?.call();
  }

  Future<void> _selectSmartView(SmartView view) async {
    try {
      final service = await ref.read(smartViewsServiceProvider.future);
      final definition = service.definitionOf(view);
      ref
          .read(noteListViewSettingsProvider.notifier)
          .apply(filter: definition.filter, order: definition.order);
      if (!mounted) return;
      _select(ref, SmartViewSection(view.id, view.name));
    } catch (error) {
      debugPrint('smart view open failed: ${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Представление повреждено или устарело'),
          ),
        );
      }
    }
  }

  void _autoScrollProjects(Offset globalPosition) {
    if (!_projectsScroll.hasClients) return;
    final renderObject = _projectsListKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    final local = renderObject.globalToLocal(globalPosition);
    const edge = 48.0;
    const step = 18.0;
    var target = _projectsScroll.offset;
    if (local.dy < edge) {
      target -= step;
    } else if (local.dy > renderObject.size.height - edge) {
      target += step;
    } else {
      return;
    }
    target = target
        .clamp(0.0, _projectsScroll.position.maxScrollExtent)
        .toDouble();
    if (target != _projectsScroll.offset) {
      _projectsScroll.jumpTo(target);
    }
  }

  Widget _dropTarget({
    required BuildContext context,
    required WidgetRef ref,
    required String? projectId,
    required Widget child,
    bool autoScroll = false,
  }) {
    return DragTarget<Note>(
      key: ValueKey('project-drop-${projectId ?? 'none'}'),
      onWillAcceptWithDetails: (details) => details.data.projectId != projectId,
      onMove: autoScroll
          ? (details) => _autoScrollProjects(details.offset)
          : null,
      onAcceptWithDetails: (details) {
        unawaited(moveNoteToProject(context, ref, details.data, projectId));
      },
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            PotokColors.of(context).radiusSmall,
          ),
          border: Border.all(
            color: candidates.isEmpty
                ? Colors.transparent
                : PotokColors.of(context).accent,
            width: 2,
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final section = ref.watch(navSectionProvider);
    final summary =
        ref.watch(navigationSummaryProvider).value ?? NavigationSummary.empty;
    final byProject =
        ref.watch(projectNoteCountsProvider).value ?? const <String, int>{};
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    final smartViews =
        ref.watch(smartViewsProvider).value ?? const <SmartView>[];
    final currentSession = ref.watch(currentSessionProvider).value;

    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border(right: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Brand(colors: c),
          _NavLabel('Заметки', colors: c),
          _NavItem(
            icon: Icons.notes_rounded,
            label: 'Все заметки',
            count: summary.total,
            active: section is AllNotesSection,
            onTap: () => _select(ref, const AllNotesSection()),
          ),
          _dropTarget(
            context: context,
            ref: ref,
            projectId: null,
            child: _NavItem(
              icon: Icons.crop_square_rounded,
              label: 'Без проекта',
              count: summary.noProject,
              active: section is NoProjectSection,
              onTap: () => _select(ref, const NoProjectSection()),
            ),
          ),
          _NavItem(
            icon: Icons.star_border_rounded,
            label: 'Избранное',
            count: summary.favorites,
            active: section is FavoritesSection,
            onTap: () => _select(ref, const FavoritesSection()),
          ),
          Row(
            children: [
              Expanded(child: _NavLabel('Проекты', colors: c)),
              IconButton(
                tooltip: 'Новый проект',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.add_rounded, size: 18, color: c.muted),
                onPressed: () => showCreateProjectDialog(context, ref),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              key: _projectsListKey,
              controller: _projectsScroll,
              padding: EdgeInsets.zero,
              children: [
                for (final project in projects)
                  _dropTarget(
                    context: context,
                    ref: ref,
                    projectId: project.id,
                    autoScroll: true,
                    child: _NavItem(
                      dotColor: Color(project.colorArgb),
                      label: project.name,
                      count: byProject[project.id] ?? 0,
                      active: section == ProjectSection(project.id),
                      onTap: () => _select(ref, ProjectSection(project.id)),
                    ),
                  ),
                if (smartViews.isNotEmpty) ...[
                  _NavLabel('Представления', colors: c),
                  for (final view in smartViews)
                    _NavItem(
                      icon: Icons.bookmark_border_rounded,
                      label: view.name,
                      active:
                          section is SmartViewSection &&
                          section.viewId == view.id,
                      onTap: () => _selectSmartView(view),
                    ),
                ],
              ],
            ),
          ),
          _NavItem(
            icon: currentSession == null
                ? Icons.play_circle_outline_rounded
                : Icons.meeting_room_outlined,
            label: currentSession?.title ?? 'Начать сессию',
            active: false,
            onTap: () {
              if (currentSession == null) {
                showStartSessionDialog(context, ref, projects);
              } else {
                showSessionHistory(
                  context,
                  initialSessionId: currentSession.id,
                );
              }
            },
          ),
          _NavItem(
            icon: Icons.history_rounded,
            label: 'История сессий',
            active: false,
            onTap: () => showSessionHistory(context),
          ),
          Divider(color: c.line, height: 17),
          _NavItem(
            icon: Icons.delete_outline_rounded,
            label: 'Корзина',
            count: summary.trash,
            active: section is TrashSection,
            onTap: () => _select(ref, const TrashSection()),
          ),
          _NavItem(
            icon: Icons.settings_outlined,
            label: 'Настройки',
            active: false,
            onTap: () => showAppearanceDialog(context, ref),
          ),
        ],
      ),
    );
  }
}

Future<void> showStartSessionDialog(
  BuildContext context,
  WidgetRef ref,
  List<Project> projects,
) async {
  if (projects.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сначала создайте проект для сессии')),
    );
    return;
  }
  final now = DateTime.now();
  final titleController = TextEditingController(
    text:
        'Сессия ${now.day.toString().padLeft(2, '0')}.'
        '${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}',
  );
  var projectId = projects.first.id;
  String? error;
  var submitting = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Новая сессия'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('session-project'),
                initialValue: projectId,
                decoration: const InputDecoration(
                  labelText: 'Проект',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final project in projects)
                    DropdownMenuItem(
                      value: project.id,
                      child: Text(project.name),
                    ),
                ],
                onChanged: submitting
                    ? null
                    : (value) {
                        if (value != null) setState(() => projectId = value);
                      },
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('session-title'),
                controller: titleController,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: 'Название',
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('start-session'),
            onPressed: submitting
                ? null
                : () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) {
                      setState(() => error = 'Введите название');
                      return;
                    }
                    setState(() {
                      submitting = true;
                      error = null;
                    });
                    try {
                      final service = await ref.read(
                        sessionsServiceProvider.future,
                      );
                      await service.start(projectId: projectId, title: title);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } catch (failure) {
                      debugPrint(
                        'session start failed: ${failure.runtimeType}',
                      );
                      if (dialogContext.mounted) {
                        setState(() {
                          submitting = false;
                          error = 'Не удалось начать сессию';
                        });
                      }
                    }
                  },
            child: const Text('Начать'),
          ),
        ],
      ),
    ),
  );
  // showDialog completes when pop starts; keep the controller alive until the
  // route's exit animation has detached its TextField.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  titleController.dispose();
}

class _Brand extends StatelessWidget {
  final PotokColors colors;
  const _Brand({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(colors.radiusSmall),
            ),
            alignment: Alignment.center,
            child: Text(
              'П',
              style: TextStyle(
                color: colors.accentText,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Поток',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
                Text(
                  'рабочие заметки',
                  style: TextStyle(fontSize: 11, color: colors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavLabel extends StatelessWidget {
  final String label;
  final PotokColors colors;
  const _NavLabel(this.label, {required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 14, 11, 7),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: colors.muted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData? icon;
  final Color? dotColor;
  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    this.icon,
    this.dotColor,
    required this.label,
    this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final foreground = active ? c.accent : c.muted;
    return Material(
      color: active ? c.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(c.radiusSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(c.radiusSmall),
        hoverColor: c.surface3,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: dotColor != null
                    ? Icon(Icons.circle, size: 10, color: dotColor)
                    : Icon(icon, size: 17, color: foreground),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: foreground,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              if (count != null)
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: active ? c.surface : c.surface3,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$count',
                    style: TextStyle(fontSize: 10, color: c.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Диалог создания проекта: имя + выбор из предустановленных цветов.
Future<void> showCreateProjectDialog(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  var selectedColor = projectPresetColors.first;
  String? error;
  var submitting = false;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final c = PotokColors.of(dialogContext);
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          Future<void> submit() async {
            final name = controller.text.trim();
            if (name.isEmpty) {
              setState(() => error = 'Введите название проекта');
              return;
            }
            setState(() {
              submitting = true;
              error = null;
            });
            try {
              final service = await ref.read(projectsServiceProvider.future);
              final id = await service.createProject(
                name: name,
                colorArgb: selectedColor,
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              ref.read(navSectionProvider.notifier).select(ProjectSection(id));
            } catch (e) {
              debugPrint('project create failed: ${e.runtimeType}');
              if (dialogContext.mounted) {
                setState(() {
                  submitting = false;
                  error = 'Не удалось создать проект';
                });
              }
            }
          }

          return AlertDialog(
            title: const Text('Новый проект'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 120,
                    decoration: InputDecoration(
                      hintText: 'Название проекта',
                      counterText: '',
                      errorText: error,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(c.radiusSmall),
                      ),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 14),
                  Text('Цвет', style: TextStyle(fontSize: 12, color: c.muted)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final color in projectPresetColors)
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => setState(() => selectedColor = color),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selectedColor == color
                                    ? c.text
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: selectedColor == color
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: submitting ? null : submit,
                child: const Text('Создать'),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(controller.dispose);
}

/// «Настройки»: выбор темы (app_meta) и секция распознавания речи.
Future<void> showAppearanceDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Consumer(
        builder: (dialogContext, dialogRef, _) {
          final c = PotokColors.of(dialogContext);
          final current =
              dialogRef.watch(themeIdProvider).value ?? PotokThemeId.studio;
          return AlertDialog(
            title: const Text('Настройки'),
            scrollable: true,
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Внешний вид',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.muted,
                      ),
                    ),
                  ),
                  for (final id in PotokThemeId.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(c.radiusSmall),
                        onTap: () async {
                          try {
                            await dialogRef
                                .read(settingsServiceProvider)
                                .set(SettingsService.themeKey, id.storageKey);
                          } catch (e) {
                            debugPrint('theme save failed: ${e.runtimeType}');
                          }
                        },
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface2,
                            border: Border.all(
                              color: current == id ? c.accent : c.line,
                            ),
                            borderRadius: BorderRadius.circular(c.radiusSmall),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      id.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: c.text,
                                      ),
                                    ),
                                    Text(
                                      id.subtitle,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: c.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (current == id)
                                Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: c.accent,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Divider(color: c.line, height: 24),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Аудиозапись и место',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.muted,
                      ),
                    ),
                  ),
                  const _AudioSettingsSection(),
                  Divider(color: c.line, height: 24),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Распознавание речи',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.muted,
                      ),
                    ),
                  ),
                  const _AsrSettingsSection(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _AudioSettingsSection extends ConsumerWidget {
  const _AudioSettingsSection();

  Future<void> _restoreAudio(
    BuildContext context,
    WidgetRef ref,
    TrashedAudioItem item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = await ref.read(notesServiceProvider.future);
      await service.restoreAudio(item.note, item.asset);
      ref.invalidate(storageUsageProvider);
    } catch (error) {
      debugPrint('audio restore failed: ${error.runtimeType}');
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось восстановить аудио')),
      );
    }
  }

  Future<void> _purgeAudio(
    BuildContext context,
    WidgetRef ref,
    TrashedAudioItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить аудио навсегда?'),
        content: const Text(
          'Файл и его ревизии расшифровки будут удалены. Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить навсегда'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = await ref.read(notesServiceProvider.future);
      await service.purgeAudio(item.note, item.asset);
      ref.invalidate(storageUsageProvider);
    } catch (error) {
      debugPrint('audio purge failed: ${error.runtimeType}');
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось удалить аудио')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final bitRate = ref.watch(audioBitRateProvider).value ?? 64000;
    final maxMinutes = ref.watch(audioMaxMinutesProvider).value ?? 30;
    final usage = ref.watch(storageUsageProvider);
    final trashed =
        ref.watch(trashedAudioProvider).value ?? const <TrashedAudioItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: bitRate,
          decoration: const InputDecoration(labelText: 'Качество записи'),
          items: const [
            DropdownMenuItem(value: 48000, child: Text('Экономное · ~21 МБ/ч')),
            DropdownMenuItem(value: 64000, child: Text('Обычное · ~28 МБ/ч')),
            DropdownMenuItem(value: 96000, child: Text('Высокое · ~42 МБ/ч')),
          ],
          onChanged: (value) {
            if (value == null) return;
            unawaited(
              ref
                  .read(settingsServiceProvider)
                  .set(SettingsService.audioBitRateKey, '$value'),
            );
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          initialValue: maxMinutes,
          decoration: const InputDecoration(
            labelText: 'Максимальная длительность',
          ),
          items: const [
            DropdownMenuItem(value: 10, child: Text('10 минут')),
            DropdownMenuItem(value: 30, child: Text('30 минут')),
            DropdownMenuItem(value: 60, child: Text('60 минут')),
            DropdownMenuItem(value: 120, child: Text('120 минут')),
          ],
          onChanged: (value) {
            if (value == null) return;
            unawaited(
              ref
                  .read(settingsServiceProvider)
                  .set(SettingsService.audioMaxMinutesKey, '$value'),
            );
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface2,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(c.radiusSmall),
          ),
          child: usage.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text('Не удалось подсчитать место'),
            data: (value) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Хранилище',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: c.text,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Обновить',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => ref.invalidate(storageUsageProvider),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ],
                ),
                Text('Аудио: ${_formatStorage(value.audioBytes)}'),
                Text('Изображения: ${_formatStorage(value.imageBytes)}'),
                Text('В корзине: ${_formatStorage(value.trashBytes)}'),
                Text('Свободно: ${_formatStorage(value.freeBytes)}'),
                if (value.missingCount > 0)
                  Text(
                    'Повреждённых/отсутствующих: ${value.missingCount}',
                    style: TextStyle(color: c.danger),
                  ),
              ],
            ),
          ),
        ),
        if (trashed.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Аудио в корзине',
            style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
          ),
          for (final item in trashed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                item.note.documentPlainText.trim().isEmpty
                    ? 'Заметка без текста'
                    : item.note.documentPlainText.split('\n').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_formatStorage(item.asset.sizeBytes)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Восстановить',
                    onPressed: () => _restoreAudio(context, ref, item),
                    icon: const Icon(Icons.restore_rounded),
                  ),
                  IconButton(
                    tooltip: 'Удалить навсегда',
                    onPressed: () => _purgeAudio(context, ref, item),
                    icon: const Icon(Icons.delete_forever_outlined),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _formatStorage(int? bytes) {
    if (bytes == null) return 'нет данных';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '$bytes Б';
  }
}

/// Секция «Распознавание речи»: активная модель и установка пака из папки.
class _AsrSettingsSection extends ConsumerStatefulWidget {
  const _AsrSettingsSection();

  @override
  ConsumerState<_AsrSettingsSection> createState() =>
      _AsrSettingsSectionState();
}

class _AsrSettingsSectionState extends ConsumerState<_AsrSettingsSection> {
  final _pathController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _error = 'Укажите путь к папке модели');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final manager = await ref.read(modelManagerProvider.future);
      final modelId = await manager.installFromDirectory(path);
      await manager.activate(modelId);
      final queue = await ref.read(transcriptionQueueProvider.future);
      await queue.kick();
      if (!mounted) return;
      _pathController.clear();
      setState(() => _busy = false);
    } on ModelPackException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      debugPrint('model install failed: ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не удалось установить модель';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final active = ref.watch(activeAsrModelProvider).value;
    final activeLabel = active == null
        ? 'Модель не установлена'
        : '${active.modelId} · ${active.languages.join(', ')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              active == null ? Icons.mic_off_outlined : Icons.mic_none_rounded,
              size: 16,
              color: active == null ? c.muted : c.decision,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                activeLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _pathController,
          enabled: !_busy,
          style: TextStyle(fontSize: 12, color: c.text),
          decoration: InputDecoration(
            hintText: 'Путь к папке model pack',
            hintStyle: TextStyle(fontSize: 12, color: c.muted),
            errorText: _error,
            errorMaxLines: 2,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(c.radiusSmall),
            ),
          ),
          onSubmitted: (_) => _install(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy ? null : _install,
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Установить из папки'),
          ),
        ),
      ],
    );
  }
}
