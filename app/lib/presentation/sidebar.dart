import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../application/note_list_query.dart';
import '../application/notes_service.dart';
import '../application/settings_service.dart';
import '../infrastructure/asr/model_manager.dart';
import '../infrastructure/db/database.dart';
import 'android_launch_intents.dart';
import 'asr_model_catalog_view.dart';
import 'data_section.dart';
import 'entity_color_palette.dart';
import 'move_note.dart';
import 'providers.dart';
import 'snackbars.dart';
import 'tag_management.dart';
import 'theme.dart';
import 'windows_integration.dart';

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
          PotokSnackBar(content: Text('Представление повреждено или устарело')),
        );
      }
    }
  }

  void _autoScrollProjects(Offset globalPosition) {
    if (!_projectsScroll.hasClients) return;
    final renderObject = _projectsListKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return;
    }
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
  var selectedColor = entityPresetColors.first;
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
                      for (final color in entityPresetColors)
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
                                ? Icon(
                                    Icons.check,
                                    size: 16,
                                    color: entityColorForeground(color),
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
                  Divider(color: c.line, height: 24),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Теги',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.muted,
                      ),
                    ),
                  ),
                  const TagManagementSection(),
                  if (windowsShellAvailable) ...[
                    Divider(color: c.line, height: 24),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Система',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: c.muted,
                        ),
                      ),
                    ),
                    const _SystemSettingsSection(),
                  ],
                  if (androidLaunchIntentsAvailable) ...[
                    Divider(color: c.line, height: 24),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Виджет Android',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: c.muted,
                        ),
                      ),
                    ),
                    const _AndroidWidgetSettingsSection(),
                  ],
                  Divider(color: c.line, height: 24),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Данные',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.muted,
                      ),
                    ),
                  ),
                  const DataSettingsSection(),
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

class _AndroidWidgetSettingsSection extends ConsumerWidget {
  const _AndroidWidgetSettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    final selectedId = ref.watch(androidWidgetProjectProvider).value;
    final validId = projects.any((project) => project.id == selectedId)
        ? selectedId
        : null;
    return DropdownButtonFormField<String>(
      key: const ValueKey('setting-android-widget-project'),
      initialValue: validId ?? '',
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Проект для быстрого ввода',
        helperText: 'Его имя показывается в виджете 2×1',
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('Без проекта')),
        for (final project in projects)
          DropdownMenuItem(value: project.id, child: Text(project.name)),
      ],
      onChanged: (value) {
        unawaited(
          ref
              .read(settingsServiceProvider)
              .set(SettingsService.androidWidgetProjectKey, value ?? '')
              .catchError((Object error) {
                debugPrint(
                  'android widget setting failed: ${error.runtimeType}',
                );
              }),
        );
      },
    );
  }
}

/// Windows-only: опциональный tray lifecycle и глобальный hotkey (ТЗ 37.8).
class _SystemSettingsSection extends ConsumerWidget {
  const _SystemSettingsSection();

  void _setFlag(WidgetRef ref, String key, bool value) {
    unawaited(
      ref.read(settingsServiceProvider).set(key, value ? '1' : '0').catchError((
        Object e,
      ) {
        debugPrint('system setting save failed: ${e.runtimeType}');
      }),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final trayEnabled = ref.watch(trayCloseEnabledProvider).value ?? false;
    final hotkeyEnabled = ref.watch(globalHotkeyEnabledProvider).value ?? false;
    final integration = ref.watch(windowsIntegrationProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('setting-tray-on-close'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Сворачивать в трей при закрытии окна'),
          subtitle: const Text('Выход — через меню значка в трее'),
          value: trayEnabled,
          onChanged: (value) =>
              _setFlag(ref, SettingsService.trayCloseKey, value),
        ),
        SwitchListTile(
          key: const ValueKey('setting-global-hotkey'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Глобальная горячая клавиша Ctrl+Alt+N'),
          subtitle: const Text('Открывает быструю заметку из любого окна'),
          value: hotkeyEnabled,
          onChanged: (value) =>
              _setFlag(ref, SettingsService.globalHotkeyKey, value),
        ),
        if (integration != null)
          ValueListenableBuilder<GlobalHotkeyStatus>(
            valueListenable: integration.hotkeyStatus,
            builder: (context, status, _) =>
                status == GlobalHotkeyStatus.conflict
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Ctrl+Alt+N занято другим приложением — глобальная '
                      'клавиша не работает, остальное работает как обычно',
                      style: TextStyle(fontSize: 11, color: c.danger),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
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
        PotokSnackBar(content: const Text('Не удалось восстановить аудио')),
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
        PotokSnackBar(content: const Text('Не удалось удалить аудио')),
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
        if (Platform.isWindows) ...[
          Text(
            'Микрофон Windows',
            style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
          ),
          const SizedBox(height: 8),
          _AudioInputDeviceSelector(),
          const SizedBox(height: 14),
        ],
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
        Text(
          'При активной offline-модели новые записи сохраняются как '
          'WAV PCM16 16 кГц (~110 МБ/ч), чтобы распознаваться без сервера. '
          'Без модели используется компактный M4A.',
          style: TextStyle(fontSize: 11, color: c.muted, height: 1.35),
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

class _AudioInputDeviceSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(audioInputDeviceIdProvider).value;
    final devicesAsync = ref.watch(audioInputDevicesProvider);
    return devicesAsync.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (_, _) => Row(
        children: [
          const Expanded(child: Text('Не удалось получить список микрофонов')),
          IconButton(
            tooltip: 'Повторить',
            onPressed: () => ref.invalidate(audioInputDevicesProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      data: (devices) {
        final selectedExists =
            selected == null || devices.any((device) => device.id == selected);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey(
                      'audio-input-${selectedExists ? selected : 'missing'}-'
                      '${devices.length}',
                    ),
                    initialValue: selectedExists ? selected : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Устройство ввода',
                      errorText: selectedExists
                          ? null
                          : 'Выбранный микрофон отключён',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Системный по умолчанию'),
                      ),
                      for (final device in devices)
                        DropdownMenuItem<String?>(
                          value: device.id,
                          child: Text(
                            device.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => unawaited(
                      ref
                          .read(settingsServiceProvider)
                          .set(
                            SettingsService.audioInputDeviceKey,
                            value ?? '',
                          ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Обновить список микрофонов',
                  onPressed: () => ref.invalidate(audioInputDevicesProvider),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Windows не сообщил ни одного устройства ввода'),
              ),
          ],
        );
      },
    );
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
  List<XFile> _pickedFiles = const [];
  String? _error;
  bool _busy = false;

  /// Путь к папке (для Windows/десктопа, где обычный доступ к диску есть).
  Future<void> _pickDirectory() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: 'Выбрать модель');
      if (path != null && mounted) {
        setState(() {
          _pathController.text = path;
          _pickedFiles = const [];
          _error = null;
        });
      }
    } catch (error) {
      debugPrint('model directory picker failed: ${error.runtimeType}');
      if (mounted) {
        setState(() => _error = 'Выбор папки недоступен на этой платформе');
      }
    }
  }

  /// Выбор отдельных файлов модели (encoder/decoder/tokens[/data]).
  ///
  /// На Android выбор ПАПКИ идёт через SAF (ACTION_OPEN_DOCUMENT_TREE):
  /// плагин реконструирует похожий на настоящий путь вида
  /// `/storage/emulated/0/...`, но обычное чтение файлов (`dart:io`) по
  /// этому пути без выданного через SAF доступа на современных Android
  /// не работает — папка «видна» (existsSync=true), а список файлов
  /// внутри — пуст. Выбор отдельных ФАЙЛОВ идёт через ACTION_OPEN_DOCUMENT
  /// и даёт полноценный доступ на чтение через ContentResolver независимо
  /// от scoped storage — поэтому именно этот путь надёжен на Android.
  Future<void> _pickFiles() async {
    try {
      // file_selector_android переводит `extensions` в MIME через системную
      // MimeTypeMap. У .onnx/.data нет известного Android'у MIME, а у .txt
      // есть ('text/plain') — если хотя бы одно расширение резолвится, а
      // остальные нет, плагин выставляет intent.setType на единственный
      // распознанный MIME и .onnx/.data пропадают из системного проводника
      // целиком. На Android поэтому не фильтруем по расширению вовсе.
      final typeGroup = Platform.isAndroid
          ? const XTypeGroup(label: 'Файлы модели', mimeTypes: ['*/*'])
          : const XTypeGroup(
              label: 'Файлы модели',
              extensions: ['onnx', 'txt', 'data'],
            );
      final files = await openFiles(acceptedTypeGroups: [typeGroup]);
      if (files.isEmpty || !mounted) return;
      setState(() {
        _pickedFiles = files;
        _pathController.clear();
        _error = null;
      });
    } catch (error) {
      debugPrint('model file picker failed: ${error.runtimeType}');
      if (mounted) {
        setState(() => _error = 'Выбор файлов недоступен на этой платформе');
      }
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    final manualPath = _pathController.text.trim();
    if (_pickedFiles.isEmpty && manualPath.isEmpty) {
      setState(() => _error = 'Выберите файлы модели или укажите папку');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    Directory? staging;
    try {
      final manager = await ref.read(modelManagerProvider.future);
      String sourcePath;
      if (_pickedFiles.isNotEmpty) {
        final tempRoot = await getTemporaryDirectory();
        staging = await Directory(
          p.join(
            tempRoot.path,
            'asr-model-import-${DateTime.now().microsecondsSinceEpoch}',
          ),
        ).create(recursive: true);
        for (final file in _pickedFiles) {
          await file.saveTo(p.join(staging.path, file.name));
        }
        sourcePath = staging.path;
      } else {
        sourcePath = manualPath;
      }
      final modelId = await manager.installWhisperDirectory(sourcePath);
      await manager.activate(modelId);
      final queue = await ref.read(transcriptionQueueProvider.future);
      await queue.kick();
      if (!mounted) return;
      _pathController.clear();
      setState(() {
        _busy = false;
        _pickedFiles = const [];
      });
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
    } finally {
      if (staging != null && staging.existsSync()) {
        await staging.delete(recursive: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final active = ref.watch(activeAsrModelProvider).value;
    final activeLabel = active == null
        ? 'Модель не установлена'
        : '${active.modelId} · ${active.languages.join(', ')} · '
              '${(active.sizeBytes / (1024 * 1024)).toStringAsFixed(0)} МБ · '
              '${active.license}';
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
        const SizedBox(height: 12),
        const AsrModelCatalogView(),
        const SizedBox(height: 4),
        Text(
          'Ручная установка из папки/файлов',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          Platform.isAndroid
              ? 'Скачайте ONNX-пак sherpa-onnx (Whisper/GigaAM/Parakeet) и '
                    'выберите файлы модели кнопкой ниже.'
              : 'Скачайте ONNX-пак sherpa-onnx (Whisper/GigaAM/Parakeet), '
                    'распакуйте и выберите папку.',
          style: TextStyle(fontSize: 11, color: c.muted, height: 1.35),
        ),
        const SizedBox(height: 8),
        // Отдельная кнопка на платформу: папка на Android ненадёжна (SAF),
        // а на Windows работает и проще для пользователя, чем выбор файлов
        // по одному.
        if (Platform.isAndroid) ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFiles,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Выбрать файлы модели'),
          ),
          if (_pickedFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Выбрано: ${_pickedFiles.map((f) => f.name).join(', ')}',
                style: TextStyle(fontSize: 11, color: c.muted),
              ),
            ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickDirectory,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Выбрать папку модели'),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _pathController,
          enabled: !_busy,
          style: TextStyle(fontSize: 12, color: c.text),
          decoration: InputDecoration(
            hintText: 'Путь к распакованной Whisper ONNX модели',
            hintStyle: TextStyle(fontSize: 12, color: c.muted),
            errorText: _error,
            errorMaxLines: 3,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(c.radiusSmall),
            ),
          ),
          onChanged: (_) {
            if (_pickedFiles.isNotEmpty) {
              setState(() => _pickedFiles = const []);
            }
          },
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
                : const Text('Проверить и установить'),
          ),
        ),
      ],
    );
  }
}
