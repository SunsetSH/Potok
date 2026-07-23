import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/note_list_query.dart';
import '../infrastructure/db/database.dart';
import 'app_shortcuts.dart';
import 'capture_sheet.dart';
import 'note_detail_pane.dart';
import 'notes_list_pane.dart';
import 'providers.dart';
import 'sidebar.dart';
import 'theme.dart';

/// Точка входа UI: ждёт готовности сервисов, затем строит адаптивный каркас.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(mediaRecoveryProvider, (previous, next) {
      if (next.hasError && previous?.error != next.error) {
        debugPrint('media recovery failed: ${next.error.runtimeType}');
      }
    });
    ref.listen(imageRecoveryProvider, (previous, next) {
      if (next.hasError && previous?.error != next.error) {
        debugPrint('image recovery failed: ${next.error.runtimeType}');
      }
    });
    final notes = ref.watch(notesServiceProvider);
    final projects = ref.watch(projectsServiceProvider);
    final tags = ref.watch(tagsServiceProvider);

    final error = notes.error ?? projects.error ?? tags.error;
    if (error != null) {
      final source = notes.hasError
          ? 'notes'
          : projects.hasError
          ? 'projects'
          : 'tags';
      debugPrint('startup $source failed: ${error.runtimeType}');
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Не удалось запустить приложение'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  ref.invalidate(notesServiceProvider);
                  ref.invalidate(projectsServiceProvider);
                  ref.invalidate(tagsServiceProvider);
                },
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    if (!notes.hasValue || !projects.hasValue || !tags.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const _Shell();
  }
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

/// Esc внутри текущего route (ТЗ 0.6.6): сначала снимает фокус с текстового
/// ввода, иначе выполняет [onEscape]. Диалоги — отдельные route'ы, их Esc
/// (DismissIntent) не затрагивается.
class EscapeScope extends StatefulWidget {
  final VoidCallback onEscape;
  final Widget child;

  const EscapeScope({super.key, required this.onEscape, required this.child});

  @override
  State<EscapeScope> createState() => _EscapeScopeState();
}

class _EscapeScopeState extends State<EscapeScope> {
  final _fallbackFocus = FocusNode(debugLabel: 'escape-scope');

  @override
  void dispose() {
    _fallbackFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _EscapeIntent(),
      },
      child: Actions(
        actions: {
          _EscapeIntent: CallbackAction<_EscapeIntent>(
            onInvoke: (_) {
              final focused = FocusManager.instance.primaryFocus;
              if (focused != null && isTextEditingFocused()) {
                focused.unfocus();
                // Keep subsequent Esc events inside this route. Without a
                // fallback focus, the next key goes to the root focus scope
                // and cannot close narrow detail or clear the selection.
                _fallbackFocus.requestFocus();
              } else {
                widget.onEscape();
              }
              return null;
            },
          ),
        },
        child: Focus(focusNode: _fallbackFocus, child: widget.child),
      ),
    );
  }
}

class _Shell extends ConsumerWidget {
  const _Shell();

  void _openNote(BuildContext context, WidgetRef ref, Note note, bool wide) {
    ref.read(selectedNoteIdProvider.notifier).select(note.id);
    if (!wide) {
      showMobileNoteDetailRoute(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          final listWidth = (constraints.maxWidth * 0.3).clamp(330.0, 430.0);
          return EscapeScope(
            // Esc на широком макете снимает выделение (ТЗ 0.6.6).
            onEscape: () {
              ref.read(bulkSelectedNoteIdsProvider.notifier).clear();
              ref.read(selectedNoteIdProvider.notifier).select(null);
            },
            child: Scaffold(
              backgroundColor: c.canvas,
              floatingActionButton: _CaptureFab(),
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Sidebar(),
                  Container(
                    width: listWidth,
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: c.line)),
                    ),
                    child: NotesListPane(
                      onOpenNote: (note) => _openNote(context, ref, note, true),
                    ),
                  ),
                  const Expanded(child: NoteDetailPane()),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: c.surface,
          floatingActionButton: _CaptureFab(),
          bottomNavigationBar: const _MobileNavigation(),
          body: SafeArea(
            child: NotesListPane(
              onOpenNote: (note) => _openNote(context, ref, note, false),
            ),
          ),
        );
      },
    );
  }
}

class _MobileNavigation extends ConsumerStatefulWidget {
  const _MobileNavigation();

  @override
  ConsumerState<_MobileNavigation> createState() => _MobileNavigationState();
}

class _MobileNavigationState extends ConsumerState<_MobileNavigation> {
  int? _selectedTab;

  void _leaveSearch() {
    ref.read(searchFocusProvider).unfocus();
  }

  void _focusSearch() {
    final focus = ref.read(searchFocusProvider);
    // Повторный requestFocus для уже focused node не поднимает Android IME.
    // Короткий re-focus делает повторное нажатие вкладки детерминированным.
    focus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      focus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            SystemChannels.textInput.invokeMethod<void>('TextInput.show'),
          );
        }
      });
    });
  }

  Future<void> _showSections(BuildContext context, WidgetRef ref) async {
    Future<void> select(NavSection section) async {
      ref.read(navSectionProvider.notifier).select(section);
      if (context.mounted) Navigator.of(context).pop();
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (sheetContext, sheetRef, _) {
          final projects =
              sheetRef.watch(projectsProvider).value ?? const <Project>[];
          final counts =
              sheetRef.watch(projectNoteCountsProvider).value ??
              const <String, int>{};
          final summary =
              sheetRef.watch(navigationSummaryProvider).value ??
              NavigationSummary.empty;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Проекты и разделы',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            showCreateProjectDialog(sheetContext, ref),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Проект'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    leading: const Icon(Icons.crop_square_rounded),
                    title: const Text('Без проекта'),
                    trailing: Text('${summary.noProject}'),
                    onTap: () => select(const NoProjectSection()),
                  ),
                  for (final project in projects)
                    ListTile(
                      leading: Icon(
                        Icons.circle,
                        size: 13,
                        color: Color(project.colorArgb),
                      ),
                      title: Text(project.name),
                      trailing: Text('${counts[project.id] ?? 0}'),
                      onTap: () => select(ProjectSection(project.id)),
                    ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: const Text('Корзина'),
                    trailing: Text('${summary.trash}'),
                    onTap: () => select(const TrashSection()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Настройки'),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await showOrganizedSettings(context);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = ref.watch(navSectionProvider);
    final searching = ref.watch(searchQueryProvider).trim().isNotEmpty;
    final sectionTab = switch (section) {
      FavoritesSection() => 2,
      AllNotesSection() => 0,
      _ => 1,
    };
    final selected = searching ? 3 : (_selectedTab == 3 ? 3 : sectionTab);
    return NavigationBar(
      selectedIndex: selected,
      height: 68,
      onDestinationSelected: (index) {
        setState(() => _selectedTab = index);
        switch (index) {
          case 0:
            _leaveSearch();
            ref.read(searchQueryProvider.notifier).set('');
            ref
                .read(navSectionProvider.notifier)
                .select(const AllNotesSection());
          case 1:
            _leaveSearch();
            unawaited(_showSections(context, ref));
          case 2:
            _leaveSearch();
            ref.read(searchQueryProvider.notifier).set('');
            ref
                .read(navSectionProvider.notifier)
                .select(const FavoritesSection());
          case 3:
            ref
                .read(navSectionProvider.notifier)
                .select(const AllNotesSection());
            _focusSearch();
        }
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.notes_outlined),
          selectedIcon: Icon(Icons.notes_rounded),
          label: 'Все',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: 'Проекты',
        ),
        NavigationDestination(
          icon: Icon(Icons.star_border_rounded),
          selectedIcon: Icon(Icons.star_rounded),
          label: 'Избранное',
        ),
        NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Поиск'),
      ],
    );
  }
}

class _CaptureFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      tooltip: 'Создать заметку (Ctrl+N)',
      onPressed: () => showCaptureSheet(context),
      child: const Icon(Icons.add_rounded, size: 26),
    );
  }
}

/// Узкий макет: detail поверх списка (push). Esc закрывает detail.
/// Маршрут к полной карточке заметки — узкий макет и deep-link из
/// Android-виджета открывают её поверх списка. Выбор заметки идёт через
/// [selectedNoteIdProvider], который читает detail-панель.
Route<void> buildNoteDetailRoute() =>
    MaterialPageRoute<void>(builder: (_) => const _DetailPage());

final _mobileNoteDetailRouteGate = MobileNoteDetailRouteGate();

/// Prevents duplicate mobile detail routes while allowing a widget deep-link
/// to change the selected note without waiting for the current route to close.
class MobileNoteDetailRouteGate {
  bool _active = false;

  void open(Future<void> Function() push) {
    if (_active) return;
    _active = true;
    unawaited(Future<void>.sync(push).whenComplete(() => _active = false));
  }
}

/// Keeps a single mobile detail surface alive. Widget deep-links can then
/// switch [selectedNoteIdProvider] immediately instead of stacking another
/// page behind the note that is already visible.
void showMobileNoteDetailRoute(BuildContext context) {
  _mobileNoteDetailRouteGate.open(
    () => Navigator.of(context).push(buildNoteDetailRoute()),
  );
}

class _DetailPage extends StatelessWidget {
  const _DetailPage();

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    return EscapeScope(
      onEscape: () => Navigator.of(context).maybePop(),
      child: Scaffold(
        backgroundColor: c.surface,
        body: const SafeArea(child: NoteDetailPane(showBack: true)),
      ),
    );
  }
}
