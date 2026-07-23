import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/voice_classification_coordinator.dart';
import '../infrastructure/db/database.dart';
import 'providers.dart';
import 'snackbars.dart';
import 'theme.dart';

/// Keeps classification UI independent from the note detail route. A
/// transcript can finish while capture is closed or the application is on a
/// different section, so confirmation belongs at the root navigator.
class VoiceClassificationHost extends ConsumerStatefulWidget {
  final Widget child;

  const VoiceClassificationHost({super.key, required this.child});

  @override
  ConsumerState<VoiceClassificationHost> createState() =>
      _VoiceClassificationHostState();
}

class _VoiceClassificationHostState
    extends ConsumerState<VoiceClassificationHost> {
  bool _draining = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(voiceClassificationEventsProvider, (previous, next) {
      if (next.isNotEmpty) _scheduleDrain();
    });
    if (ref.read(voiceClassificationEventsProvider).isNotEmpty) {
      _scheduleDrain();
    }
    return widget.child;
  }

  void _scheduleDrain() {
    if (_draining) return;
    _draining = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  Future<void> _drain() async {
    try {
      while (mounted) {
        final event = ref
            .read(voiceClassificationEventsProvider.notifier)
            .takeFirst();
        if (event == null) break;
        await _present(event);
      }
    } finally {
      _draining = false;
      if (mounted && ref.read(voiceClassificationEventsProvider).isNotEmpty) {
        _scheduleDrain();
      }
    }
  }

  Future<void> _present(VoiceClassificationResult result) async {
    final suggestion = result.suggestion;
    if (result.disposition == VoiceClassificationDisposition.applied) {
      appScaffoldMessengerKey.currentState?.showSnackBar(
        PotokSnackBar(
          content: Text(_summary(suggestion.tags, suggestion.project)),
        ),
      );
      return;
    }

    final navigatorContext = appNavigatorKey.currentContext;
    if (navigatorContext == null) return;
    final decision = await showDialog<_ClassificationDecision>(
      context: navigatorContext,
      useRootNavigator: true,
      builder: (_) => _ClassificationConfirmDialog(
        tags: suggestion.tags,
        project: suggestion.project,
      ),
    );
    if (decision == null || !mounted) return;
    final confirmed = VoiceClassificationSuggestion(
      noteId: suggestion.noteId,
      tags: decision.tags,
      project: decision.project,
    );
    if (confirmed.isEmpty) return;

    try {
      final coordinator = await ref.read(
        voiceClassificationCoordinatorProvider.future,
      );
      await coordinator.apply(confirmed);
      appScaffoldMessengerKey.currentState?.showSnackBar(
        PotokSnackBar(
          content: Text(_summary(confirmed.tags, confirmed.project)),
        ),
      );
    } catch (error) {
      debugPrint('voice classification apply failed: ${error.runtimeType}');
      appScaffoldMessengerKey.currentState?.showSnackBar(
        PotokSnackBar(
          content: const Text('Не удалось применить классификацию'),
        ),
      );
    }
  }
}

String _summary(List<Tag> tags, Project? project) {
  final parts = <String>[];
  if (tags.isNotEmpty) {
    parts.add('теги: ${tags.map((t) => t.name).join(', ')}');
  }
  if (project != null) parts.add('проект: ${project.name}');
  return 'Из речи распознано — ${parts.join('; ')}';
}

class _ClassificationDecision {
  final List<Tag> tags;
  final Project? project;

  const _ClassificationDecision({required this.tags, required this.project});
}

class _ClassificationConfirmDialog extends StatefulWidget {
  final List<Tag> tags;
  final Project? project;

  const _ClassificationConfirmDialog({required this.tags, this.project});

  @override
  State<_ClassificationConfirmDialog> createState() =>
      _ClassificationConfirmDialogState();
}

class _ClassificationConfirmDialogState
    extends State<_ClassificationConfirmDialog> {
  late final Set<String> _checkedTagIds = widget.tags.map((t) => t.id).toSet();
  late bool _applyProject = widget.project != null;

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    return AlertDialog(
      title: const Text('Распознано в речи'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.tags.isNotEmpty)
            Text('Теги', style: TextStyle(fontSize: 12, color: c.muted)),
          for (final tag in widget.tags)
            CheckboxListTile(
              key: ValueKey('classify-tag-${tag.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _checkedTagIds.contains(tag.id),
              onChanged: (value) => setState(() {
                if (value ?? false) {
                  _checkedTagIds.add(tag.id);
                } else {
                  _checkedTagIds.remove(tag.id);
                }
              }),
              secondary: Icon(
                Icons.circle,
                size: 12,
                color: Color(tag.colorArgb),
              ),
              title: Text(tag.name),
            ),
          if (widget.project != null) ...[
            const SizedBox(height: 4),
            Text('Проект', style: TextStyle(fontSize: 12, color: c.muted)),
            CheckboxListTile(
              key: const ValueKey('classify-project'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _applyProject,
              onChanged: (value) =>
                  setState(() => _applyProject = value ?? false),
              secondary: Icon(
                Icons.folder_rounded,
                size: 16,
                color: Color(widget.project!.colorArgb),
              ),
              title: Text('Перенести в «${widget.project!.name}»'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('classify-apply'),
          onPressed: () => Navigator.of(context).pop(
            _ClassificationDecision(
              tags: widget.tags
                  .where((t) => _checkedTagIds.contains(t.id))
                  .toList(growable: false),
              project: _applyProject ? widget.project : null,
            ),
          ),
          child: const Text('Применить'),
        ),
      ],
    );
  }
}
