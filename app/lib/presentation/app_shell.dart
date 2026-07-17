import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import 'capture_sheet.dart';
import 'note_detail_pane.dart';
import 'notes_list_pane.dart';
import 'providers.dart';
import 'session_history.dart';
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
    ref.listen(sessionRecoveryProvider, (previous, next) {
      if (next.hasError && previous?.error != next.error) {
        debugPrint('session recovery failed: ${next.error.runtimeType}');
      }
    });
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const _Shell();
  }
}

class _Shell extends ConsumerWidget {
  const _Shell();

  void _openNote(BuildContext context, WidgetRef ref, Note note, bool wide) {
    ref.read(selectedNoteIdProvider.notifier).select(note.id);
    if (!wide) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const _DetailPage()));
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
          return Scaffold(
            backgroundColor: c.canvas,
            floatingActionButton: _CaptureFab(),
            bottomNavigationBar: const _SessionBar(),
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
              builder: (drawerContext) =>
                  Sidebar(onNavigate: () => Navigator.of(drawerContext).pop()),
            ),
          ),
          floatingActionButton: _CaptureFab(),
          bottomNavigationBar: const _SessionBar(),
          body: SafeArea(
            child: Builder(
              builder: (bodyContext) => NotesListPane(
                showMenuButton: true,
                onOpenNote: (note) => _openNote(bodyContext, ref, note, false),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SessionBar extends ConsumerStatefulWidget {
  const _SessionBar();

  @override
  ConsumerState<_SessionBar> createState() => _SessionBarState();
}

class _SessionBarState extends ConsumerState<_SessionBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _run(Session session, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('session action failed: ${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Состояние сессии уже изменилось')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider).value;
    if (session == null) return const SizedBox.shrink();
    final c = PotokColors.of(context);
    final elapsed = DateTime.now().toUtc().difference(
      DateTime.fromMillisecondsSinceEpoch(session.startedAtUtc, isUtc: true),
    );
    final safeElapsed = elapsed.isNegative ? Duration.zero : elapsed;
    final hours = safeElapsed.inHours.toString().padLeft(2, '0');
    final minutes = (safeElapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (safeElapsed.inSeconds % 60).toString().padLeft(2, '0');
    final active = session.state == SessionState.active;

    return Material(
      color: c.surface2,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              children: [
                Icon(
                  active ? Icons.meeting_room_rounded : Icons.pause_circle,
                  color: active ? c.accent : c.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    key: const ValueKey('open-current-session-history'),
                    borderRadius: BorderRadius.circular(c.radiusSmall),
                    onTap: () => showSessionHistory(
                      context,
                      initialSessionId: session.id,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${active ? 'Активна' : 'Приостановлена'} · '
                          '$hours:$minutes:$seconds',
                          style: TextStyle(color: c.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('session-capture'),
                  tooltip: 'Новая заметка в сессии',
                  onPressed: active
                      ? () => showCaptureSheet(context, sessionId: session.id)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
                IconButton(
                  key: const ValueKey('session-pause-resume'),
                  tooltip: active ? 'Приостановить' : 'Продолжить',
                  onPressed: () async {
                    final service = await ref.read(
                      sessionsServiceProvider.future,
                    );
                    await _run(
                      session,
                      () => active
                          ? service.pause(session)
                          : service.resume(session),
                    );
                  },
                  icon: Icon(
                    active ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                TextButton(
                  key: const ValueKey('session-complete'),
                  onPressed: () async {
                    final service = await ref.read(
                      sessionsServiceProvider.future,
                    );
                    await _run(session, () => service.complete(session));
                  },
                  child: const Text('Завершить'),
                ),
              ],
            ),
          ),
        ),
      ),
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
