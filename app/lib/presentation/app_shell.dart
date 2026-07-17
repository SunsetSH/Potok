import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/db/database.dart';
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
    final notes = ref.watch(notesServiceProvider);
    final projects = ref.watch(projectsServiceProvider);
    final tags = ref.watch(tagsServiceProvider);

    final error = notes.error ?? projects.error ?? tags.error;
    if (error != null) {
      debugPrint('startup failed: ${error.runtimeType}');
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const _Shell();
  }
}

class _Shell extends ConsumerWidget {
  const _Shell();

  void _openNote(BuildContext context, WidgetRef ref, Note note, bool wide) {
    ref.read(selectedNoteIdProvider.notifier).select(note.id);
    if (!wide) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const _DetailPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          final listWidth =
              (constraints.maxWidth * 0.3).clamp(330.0, 430.0);
          return Scaffold(
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
          );
        }
        return Scaffold(
          backgroundColor: c.surface,
          drawer: Drawer(
            backgroundColor: c.surface2,
            child: Builder(
              builder: (drawerContext) => Sidebar(
                onNavigate: () => Navigator.of(drawerContext).pop(),
              ),
            ),
          ),
          floatingActionButton: _CaptureFab(),
          body: SafeArea(
            child: Builder(
              builder: (bodyContext) => NotesListPane(
                showMenuButton: true,
                onOpenNote: (note) =>
                    _openNote(bodyContext, ref, note, false),
              ),
            ),
          ),
        );
      },
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

/// Узкий макет: detail поверх списка (push).
class _DetailPage extends StatelessWidget {
  const _DetailPage();

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      body: const SafeArea(child: NoteDetailPane(showBack: true)),
    );
  }
}
