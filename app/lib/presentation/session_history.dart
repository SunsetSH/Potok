import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import 'providers.dart';
import 'theme.dart';

Future<void> showSessionHistory(
  BuildContext context, {
  String? initialSessionId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _SessionHistory(initialSessionId: initialSessionId),
    ),
  );
}

class _SessionHistory extends ConsumerStatefulWidget {
  final String? initialSessionId;

  const _SessionHistory({this.initialSessionId});

  @override
  ConsumerState<_SessionHistory> createState() => _SessionHistoryState();
}

class _SessionHistoryState extends ConsumerState<_SessionHistory> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSessionId;
  }

  Future<void> _rename(Session session) async {
    final controller = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Переименовать сессию'),
        content: TextField(
          key: const ValueKey('rename-session-title'),
          controller: controller,
          autofocus: true,
          maxLength: 200,
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
            key: const ValueKey('confirm-session-rename'),
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
    if (title == null || !mounted) return;
    await _guarded(() async {
      final service = await ref.read(sessionsServiceProvider.future);
      await service.rename(session, title);
    });
  }

  Future<void> _delete(Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить сессию?'),
        content: const Text(
          'Будет удалён только контекст сессии. Все заметки сохранятся в проекте.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('confirm-session-delete'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить сессию'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _guarded(() async {
      final service = await ref.read(sessionsServiceProvider.future);
      await service.deleteKeepingNotes(session);
      if (mounted) setState(() => _selectedId = null);
    });
  }

  Future<void> _guarded(Future<void> Function() action) async {
    try {
      await action();
    } on StateError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сессия уже изменилась — список обновлён'),
          ),
        );
      }
    } catch (error) {
      debugPrint('session history action failed: ${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось изменить сессию')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final sessionsAsync = ref.watch(sessionsProvider);
    final sessions = sessionsAsync.value;
    if (sessions == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (sessions.isEmpty) {
      return Center(
        child: Text('Сессий пока нет', style: TextStyle(color: c.muted)),
      );
    }
    Session selected = sessions.first;
    for (final session in sessions) {
      if (session.id == _selectedId) {
        selected = session;
        break;
      }
    }
    final notesAsync = ref.watch(sessionNotesProvider(selected.id));
    final notes = notesAsync.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'История сессий',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: DropdownButtonFormField<String>(
            key: const ValueKey('session-history-selector'),
            initialValue: selected.id,
            decoration: const InputDecoration(labelText: 'Сессия'),
            items: [
              for (final session in sessions)
                DropdownMenuItem(
                  value: session.id,
                  child: Text(
                    '${session.title} · ${_shortDate(session.startedAtUtc)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _selectedId = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _sessionStateLabel(selected),
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
              IconButton(
                key: const ValueKey('rename-session'),
                tooltip: 'Переименовать',
                onPressed: () => _rename(selected),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: const ValueKey('delete-session'),
                tooltip: 'Удалить, сохранив заметки',
                onPressed: () => _delete(selected),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: c.line),
        Expanded(
          child: notes == null
              ? const Center(child: CircularProgressIndicator())
              : notes.isEmpty
              ? Center(
                  child: Text(
                    'В этой сессии нет заметок',
                    style: TextStyle(color: c.muted),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('session-timeline'),
                  padding: const EdgeInsets.all(16),
                  itemCount: notes.length,
                  itemBuilder: (context, index) => _TimelineEntry(
                    note: notes[index],
                    startedAtUtc: selected.startedAtUtc,
                  ),
                ),
        ),
      ],
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final Note note;
  final int startedAtUtc;

  const _TimelineEntry({required this.note, required this.startedAtUtc});

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final text = note.documentPlainText.trim();
    final title = text.isEmpty ? 'Аудиозаметка' : text.split('\n').first;
    final absolute = DateTime.fromMillisecondsSinceEpoch(
      note.createdAtUtc,
      isUtc: true,
    ).toLocal();
    final offsetMillis = note.createdAtUtc - startedAtUtc;
    final offset = Duration(milliseconds: offsetMillis < 0 ? 0 : offsetMillis);
    final semantics =
        '${_clock(absolute)}, смещение ${_offset(offset)}, $title';
    return Semantics(
      label: semantics,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(c.radiusSmall),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 82,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _clock(absolute),
                    style: TextStyle(color: c.text, fontSize: 12),
                  ),
                  Text(
                    _offset(offset),
                    key: ValueKey('session-offset-${note.id}'),
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.text, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _sessionStateLabel(Session session) {
  final state = switch (session.state) {
    SessionState.active => 'Активна',
    SessionState.paused => 'Приостановлена',
    SessionState.completed => 'Завершена',
  };
  return '$state · ${_shortDate(session.startedAtUtc)}';
}

String _shortDate(int utcMillis) {
  final date = DateTime.fromMillisecondsSinceEpoch(
    utcMillis,
    isUtc: true,
  ).toLocal();
  return '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.${date.year}';
}

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}';

String _offset(Duration value) {
  final hours = value.inHours.toString().padLeft(2, '0');
  final minutes = (value.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  return '+$hours:$minutes:$seconds';
}
