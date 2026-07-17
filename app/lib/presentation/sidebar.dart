import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/settings_service.dart';
import '../infrastructure/asr/model_manager.dart';
import '../infrastructure/db/database.dart';
import 'providers.dart';
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
class Sidebar extends ConsumerWidget {
  /// Закрывает Drawer на узком макете после выбора раздела.
  final VoidCallback? onNavigate;

  const Sidebar({super.key, this.onNavigate});

  void _select(WidgetRef ref, NavSection section) {
    ref.read(navSectionProvider.notifier).select(section);
    onNavigate?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final section = ref.watch(navSectionProvider);
    final notes = ref.watch(allNotesProvider).value ?? const <Note>[];
    final trash = ref.watch(trashNotesProvider).value ?? const <Note>[];
    final projects =
        ref.watch(projectsProvider).value ?? const <Project>[];

    final noProjectCount = notes.where((n) => n.projectId == null).length;
    final favoritesCount = notes.where((n) => n.isFavorite).length;
    final byProject = <String, int>{};
    for (final note in notes) {
      final id = note.projectId;
      if (id != null) byProject[id] = (byProject[id] ?? 0) + 1;
    }

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
            count: notes.length,
            active: section is AllNotesSection,
            onTap: () => _select(ref, const AllNotesSection()),
          ),
          _NavItem(
            icon: Icons.crop_square_rounded,
            label: 'Без проекта',
            count: noProjectCount,
            active: section is NoProjectSection,
            onTap: () => _select(ref, const NoProjectSection()),
          ),
          _NavItem(
            icon: Icons.star_border_rounded,
            label: 'Избранное',
            count: favoritesCount,
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
              padding: EdgeInsets.zero,
              children: [
                for (final project in projects)
                  _NavItem(
                    dotColor: Color(project.colorArgb),
                    label: project.name,
                    count: byProject[project.id] ?? 0,
                    active: section == ProjectSection(project.id),
                    onTap: () => _select(ref, ProjectSection(project.id)),
                  ),
              ],
            ),
          ),
          Divider(color: c.line, height: 17),
          _NavItem(
            icon: Icons.delete_outline_rounded,
            label: 'Корзина',
            count: trash.length,
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
                Text('Поток',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.text)),
                Text('рабочие заметки',
                    style: TextStyle(fontSize: 11, color: colors.muted)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              final service =
                  await ref.read(projectsServiceProvider.future);
              final id = await service.createProject(
                  name: name, colorArgb: selectedColor);
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
                  Text('Цвет',
                      style: TextStyle(fontSize: 12, color: c.muted)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final color in projectPresetColors)
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () =>
                              setState(() => selectedColor = color),
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
                                ? const Icon(Icons.check,
                                    size: 16, color: Colors.white)
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
          final current = dialogRef.watch(themeIdProvider).value ??
              PotokThemeId.studio;
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
                    child: Text('Внешний вид',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c.muted)),
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
                            debugPrint(
                                'theme save failed: ${e.runtimeType}');
                          }
                        },
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: c.surface2,
                            border: Border.all(
                              color: current == id ? c.accent : c.line,
                            ),
                            borderRadius:
                                BorderRadius.circular(c.radiusSmall),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(id.title,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: c.text)),
                                    Text(id.subtitle,
                                        style: TextStyle(
                                            fontSize: 11, color: c.muted)),
                                  ],
                                ),
                              ),
                              if (current == id)
                                Icon(Icons.check_rounded,
                                    size: 18, color: c.accent),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Divider(color: c.line, height: 24),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Распознавание речи',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c.muted)),
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
              active == null
                  ? Icons.mic_off_outlined
                  : Icons.mic_none_rounded,
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
