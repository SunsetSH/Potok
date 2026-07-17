import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/notes_service.dart';
import '../domain/document.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import 'providers.dart';
import 'sidebar.dart';
import 'theme.dart';

enum _SaveStatus { saved, saving, error }

/// Detail-панель: toolbar со статусом сохранения, проект, теги,
/// текст с автосохранением (debounce 500 мс) и аудиоблок с ревизиями.
class NoteDetailPane extends ConsumerStatefulWidget {
  /// Кнопка «назад» на узком макете (панель открыта поверх списка).
  final bool showBack;

  const NoteDetailPane({super.key, this.showBack = false});

  @override
  ConsumerState<NoteDetailPane> createState() => _NoteDetailPaneState();
}

class _NoteDetailPaneState extends ConsumerState<NoteDetailPane> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String? _noteId;
  Note? _latest;
  bool _dirty = false;
  bool _saving = false;
  _SaveStatus _status = _SaveStatus.saved;

  @override
  void dispose() {
    _debounce?.cancel();
    // Панель закрыта с несохранённым текстом — дописываем без ожидания,
    // чтобы правка не потерялась (durable-сразу, ТЗ 0.1).
    final note = _latest;
    if (_dirty && note != null) {
      final service = ref.read(notesServiceProvider).value;
      if (service != null) {
        unawaited(service
            .updateDocument(note, PotokDocument.fromPlainText(_controller.text))
            .catchError((Object e) {
          debugPrint('note flush failed: ${e.runtimeType}');
        }));
      }
    }
    _controller.dispose();
    super.dispose();
  }

  /// Проекция текста редактора в plain text документа (для сравнения
  /// «есть ли несохранённые изменения» без ложных срабатываний).
  String _projected(String raw) => PotokDocument.fromPlainText(raw).plainText;

  void _sync(Note? note) {
    if (note == null) {
      _noteId = null;
      _latest = null;
      return;
    }
    if (note.id != _noteId) {
      _debounce?.cancel();
      _noteId = note.id;
      _latest = note;
      _dirty = false;
      _saving = false;
      _status = _SaveStatus.saved;
      _controller.text = note.documentPlainText;
      return;
    }
    _latest = note;
    if (!_dirty &&
        !_saving &&
        _projected(_controller.text) != note.documentPlainText) {
      // Внешнее изменение (принятая расшифровка, другая панель).
      _controller.text = note.documentPlainText;
    }
  }

  void _onChanged(String _) {
    _dirty = true;
    if (_status != _SaveStatus.saving) {
      setState(() => _status = _SaveStatus.saving);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    if (_saving) {
      // Сохранение уже идёт — дожидаемся и пробуем снова.
      _debounce = Timer(const Duration(milliseconds: 300), _save);
      return;
    }
    final note = _latest;
    if (note == null) return;
    final document = PotokDocument.fromPlainText(_controller.text);
    if (document.plainText == note.documentPlainText) {
      setState(() {
        _dirty = false;
        _status = _SaveStatus.saved;
      });
      return;
    }
    _saving = true;
    try {
      await ref
          .read(notesServiceProvider)
          .requireValue
          .updateDocument(note, document);
      // Локально фиксируем новую ревизию, не дожидаясь потока: следующее
      // автосохранение не должно упасть на stale revision.
      _latest = note.copyWith(
        documentJson: document.encode(),
        documentPlainText: document.plainText,
        revision: note.revision + 1,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = _projected(_controller.text) != document.plainText;
        _status = _dirty ? _SaveStatus.saving : _SaveStatus.saved;
      });
      if (_dirty) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 500), _save);
      }
    } on StateError {
      // Конкурентное изменение: показываем актуальную версию из потока.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _status = _SaveStatus.saved;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Заметка изменена в другом месте — показана актуальная версия')));
    } catch (e) {
      debugPrint('note save failed: ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = _SaveStatus.error;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить заметку')));
    }
  }

  Future<void> _guarded(Future<void> Function(NotesService service) action,
      {String? failMessage}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = await ref.read(notesServiceProvider.future);
      await action(service);
    } on StateError {
      messenger.showSnackBar(const SnackBar(
          content: Text('Данные изменились — показана актуальная версия')));
    } catch (e) {
      debugPrint('note action failed: ${e.runtimeType}');
      messenger.showSnackBar(SnackBar(
          content: Text(failMessage ?? 'Не удалось выполнить действие')));
    }
  }

  Future<void> _moveToProject(Note note) async {
    final projects =
        ref.read(projectsProvider).value ?? const <Project>[];
    final c = PotokColors.of(context);
    final selected = await showDialog<_MoveTarget>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Перенести в проект'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(dialogContext).pop(const _MoveTarget(null)),
            child: Row(
              children: [
                Icon(Icons.crop_square_rounded, size: 14, color: c.muted),
                const SizedBox(width: 10),
                const Text('Без проекта'),
              ],
            ),
          ),
          for (final project in projects)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_MoveTarget(project.id)),
              child: Row(
                children: [
                  Icon(Icons.circle,
                      size: 12, color: Color(project.colorArgb)),
                  const SizedBox(width: 10),
                  Flexible(child: Text(project.name)),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    await _guarded(
      (service) => service.moveToProject(note, selected.projectId),
      failMessage: 'Не удалось перенести заметку',
    );
  }

  Future<void> _moveToTrash(Note note) async {
    await _guarded((service) => service.moveToTrash(note),
        failMessage: 'Не удалось удалить заметку');
    if (!mounted) return;
    ref.read(selectedNoteIdProvider.notifier).select(null);
    if (widget.showBack && context.mounted) {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final note = ref.watch(selectedNoteProvider);
    _sync(note);

    if (note == null) {
      return Container(
        color: c.surface,
        alignment: Alignment.center,
        child: Text('Выберите заметку',
            style: TextStyle(color: c.muted, fontSize: 13)),
      );
    }

    return Container(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(
            note: note,
            status: _status,
            showBack: widget.showBack,
            onFavorite: () => _guarded(
                (service) => service.setFavorite(note, !note.isFavorite)),
            onToggleDone: () =>
                _guarded((service) => service.toggleDone(note)),
            onMove: () => _moveToProject(note),
            onTrash: () => _moveToTrash(note),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                _ProjectRow(note: note),
                const SizedBox(height: 14),
                _TagsRow(note: note),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(fontSize: 16, height: 1.72, color: c.text),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Текст заметки…',
                    hintStyle: TextStyle(color: c.muted),
                  ),
                ),
                if (note.sourceKind == SourceKind.audio) ...[
                  const SizedBox(height: 26),
                  _AudioSection(note: note),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveTarget {
  final String? projectId;
  const _MoveTarget(this.projectId);
}

class _Toolbar extends StatelessWidget {
  final Note note;
  final _SaveStatus status;
  final bool showBack;
  final VoidCallback onFavorite;
  final VoidCallback onToggleDone;
  final VoidCallback onMove;
  final VoidCallback onTrash;

  const _Toolbar({
    required this.note,
    required this.status,
    required this.showBack,
    required this.onFavorite,
    required this.onToggleDone,
    required this.onMove,
    required this.onTrash,
  });

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final done = note.status == NoteStatus.done;
    final (dotColor, label) = switch (status) {
      _SaveStatus.saved => (c.decision, 'Все изменения сохранены'),
      _SaveStatus.saving => (c.muted, 'Сохраняется…'),
      _SaveStatus.error => (c.danger, 'Ошибка сохранения'),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          if (showBack)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Назад',
                icon: Icon(Icons.arrow_back_rounded, color: c.text),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          Expanded(
            child: Row(
              children: [
                Icon(Icons.circle, size: 8, color: dotColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: dotColor),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: note.isFavorite ? 'Убрать из избранного' : 'В избранное',
            icon: Icon(
              note.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: note.isFavorite ? c.accent : c.muted,
            ),
            onPressed: onFavorite,
          ),
          IconButton(
            tooltip: done ? 'Вернуть в работу' : 'Выполнено',
            icon: Icon(
              done ? Icons.check_circle_rounded : Icons.check_circle_outline,
              color: done ? c.decision : c.muted,
            ),
            onPressed: onToggleDone,
          ),
          PopupMenuButton<String>(
            tooltip: 'Другие действия',
            icon: Icon(Icons.more_horiz_rounded, color: c.muted),
            onSelected: (value) {
              if (value == 'move') onMove();
              if (value == 'trash') onTrash();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'move', child: Text('Перенести в проект…')),
              PopupMenuItem(
                value: 'trash',
                child: Text('В корзину',
                    style: TextStyle(color: c.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectRow extends ConsumerWidget {
  final Note note;
  const _ProjectRow({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final projects =
        ref.watch(projectsProvider).value ?? const <Project>[];
    Project? project;
    for (final p in projects) {
      if (p.id == note.projectId) {
        project = p;
        break;
      }
    }
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: project != null ? Color(project.colorArgb) : c.muted,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            project?.name ?? 'Без проекта',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ),
      ],
    );
  }
}

class _TagsRow extends ConsumerWidget {
  final Note note;

  const _TagsRow({required this.note});

  Future<void> _runTagAction(BuildContext context, WidgetRef ref,
      Future<void> Function() action, String failMessage) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on StateError {
      messenger.showSnackBar(const SnackBar(
          content: Text('Тег недоступен для этой заметки')));
    } catch (e) {
      debugPrint('tag action failed: ${e.runtimeType}');
      messenger.showSnackBar(SnackBar(content: Text(failMessage)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final noteTags =
        ref.watch(noteTagsProvider(note.id)).value ?? const <Tag>[];
    final available = ref.watch(availableTagsProvider(note.projectId)).value ??
        const <Tag>[];
    final assignedIds = noteTags.map((t) => t.id).toSet();
    final addable = available
        .where((t) => !assignedIds.contains(t.id))
        .toList(growable: false);

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final tag in noteTags)
          Tooltip(
            message: 'Снять тег',
            waitDuration: const Duration(milliseconds: 600),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _runTagAction(
                context,
                ref,
                () async {
                  final service = await ref.read(tagsServiceProvider.future);
                  await service.unassignTag(note.id, tag.id);
                },
                'Не удалось снять тег',
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Color(tag.colorArgb).withValues(alpha: 0.12),
                  border: Border.all(
                      color: Color(tag.colorArgb).withValues(alpha: 0.45)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tag.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(tag.colorArgb),
                  ),
                ),
              ),
            ),
          ),
        if (addable.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Добавить тег',
            onSelected: (tagId) => _runTagAction(
              context,
              ref,
              () async {
                final service = await ref.read(tagsServiceProvider.future);
                await service.assignTag(note.id, tagId);
              },
              'Не удалось добавить тег',
            ),
            itemBuilder: (context) => [
              for (final tag in addable)
                PopupMenuItem(
                  value: tag.id,
                  child: Row(
                    children: [
                      Icon(Icons.circle,
                          size: 10, color: Color(tag.colorArgb)),
                      const SizedBox(width: 8),
                      Flexible(child: Text(tag.name)),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('+ тег',
                  style: TextStyle(fontSize: 11, color: c.muted)),
            ),
          ),
      ],
    );
  }
}

/// Аудиоблок: исходная запись + постановка ASR в очередь + ревизии.
/// Прогресс job'а виден через состояния TranscriptRevision (очередь durable,
/// локального «идёт расшифровка» флага нет).
class _AudioSection extends ConsumerWidget {
  final Note note;
  const _AudioSection({required this.note});

  Future<void> _enqueue(
      BuildContext context, WidgetRef ref, String assetId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final queue = await ref.read(transcriptionQueueProvider.future);
      await queue.enqueue(note.id, assetId);
    } catch (e) {
      debugPrint('enqueue transcription failed: ${e.runtimeType}');
      messenger.showSnackBar(const SnackBar(
          content: Text('Не удалось поставить расшифровку в очередь')));
    }
  }

  Future<void> _retry(
      BuildContext context, WidgetRef ref, String revisionId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final queue = await ref.read(transcriptionQueueProvider.future);
      await queue.retry(revisionId);
    } catch (e) {
      debugPrint('retry transcription failed: ${e.runtimeType}');
      messenger.showSnackBar(
          const SnackBar(content: Text('Не удалось повторить расшифровку')));
    }
  }

  Future<void> _accept(
      BuildContext context, WidgetRef ref, String revisionId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = await ref.read(notesServiceProvider.future);
      await service.acceptTranscript(note.id, revisionId);
    } on StateError {
      messenger.showSnackBar(const SnackBar(
          content: Text('Заметка изменилась — повторите принятие')));
    } catch (e) {
      debugPrint('accept transcript failed: ${e.runtimeType}');
      messenger.showSnackBar(
          const SnackBar(content: Text('Не удалось принять расшифровку')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final asset = ref.watch(readyAudioAssetProvider(note.id)).value;
    final revisions = ref.watch(revisionsProvider(note.id)).value ??
        const <TranscriptRevision>[];
    if (asset == null) return const SizedBox.shrink();

    final inFlight = revisions.any((r) =>
        r.state == TranscriptState.queued ||
        r.state == TranscriptState.recognizing);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.line, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.play_arrow_rounded, size: 16, color: c.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Исходное аудио · ${(asset.sizeBytes / 1024).ceil()} КБ · WAV',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
              TextButton(
                onPressed:
                    inFlight ? null : () => _enqueue(context, ref, asset.id),
                child: const Text('Расшифровать'),
              ),
            ],
          ),
          for (final revision in revisions)
            _RevisionTile(
              revision: revision,
              onAccept: (id) => _accept(context, ref, id),
              onRetry: (id) => _retry(context, ref, id),
              onConfigure: () => showAppearanceDialog(context, ref),
            ),
        ],
      ),
    );
  }
}

class _RevisionTile extends StatelessWidget {
  final TranscriptRevision revision;
  final Future<void> Function(String revisionId) onAccept;
  final Future<void> Function(String revisionId) onRetry;
  final VoidCallback onConfigure;

  const _RevisionTile({
    required this.revision,
    required this.onAccept,
    required this.onRetry,
    required this.onConfigure,
  });

  Widget _statusRow(PotokColors c, String label, Color labelColor,
      {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child:
                Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
          ),
          ?action,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    switch (revision.state) {
      case TranscriptState.ready:
        final accepted = revision.acceptedAtUtc != null;
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(c.radiusSmall),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  revision.rawText.isEmpty ? '(пусто)' : revision.rawText,
                  style: TextStyle(fontSize: 12, color: c.text),
                ),
              ),
              if (accepted)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child:
                      Icon(Icons.check_rounded, size: 16, color: c.decision),
                )
              else
                TextButton(
                  onPressed: () => onAccept(revision.id),
                  child: const Text('Принять'),
                ),
            ],
          ),
        );
      case TranscriptState.recognizing:
      case TranscriptState.queued:
        return const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(minHeight: 2),
        );
      case TranscriptState.failed:
        return _statusRow(
          c,
          'Ошибка расшифровки',
          c.danger,
          action: TextButton(
            onPressed: () => onRetry(revision.id),
            child: const Text('Повторить'),
          ),
        );
      case TranscriptState.cancelled:
        return _statusRow(
          c,
          'Расшифровка отменена',
          c.muted,
          action: TextButton(
            onPressed: () => onRetry(revision.id),
            child: const Text('Повторить'),
          ),
        );
      case TranscriptState.waitingForModel:
        return _statusRow(
          c,
          'Модель не установлена',
          c.muted,
          action: TextButton(
            onPressed: onConfigure,
            child: const Text('Настроить'),
          ),
        );
    }
  }
}
