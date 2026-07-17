import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../application/drafts_service.dart';
import '../application/notes_service.dart';
import '../domain/document.dart';
import '../infrastructure/db/database.dart';
import 'providers.dart';
import 'theme.dart';

bool _captureOpen = false;

/// Quick capture (FAB, Ctrl+N): диалог на широком экране, шторка на узком.
Future<void> showCaptureSheet(BuildContext context) async {
  if (_captureOpen) return;
  _captureOpen = true;
  try {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: const CaptureSheet(),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const CaptureSheet(),
      );
    }
  } finally {
    _captureOpen = false;
  }
}

/// Быстрая заметка: текст + аудио в одной поверхности (FR-NOT-001/002).
/// Черновик durable: debounce 500 мс → DraftsService('quick-capture');
/// закрытие крестиком/Esc черновик НЕ удаляет (FR-NOT-004).
class CaptureSheet extends ConsumerStatefulWidget {
  const CaptureSheet({super.key});

  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  static const _surfaceId = 'quick-capture';
  static const _sampleRate = 16000;

  final _controller = TextEditingController();
  final _recorder = AudioRecorder();

  late final DraftsService _drafts = ref.read(draftsServiceProvider);

  Timer? _draftDebounce;
  bool _draftDirty = false;
  String? _projectId;

  StagedRecording? _staged;
  DateTime? _recordingStarted;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  String? _error;
  bool _savingNote = false;

  /// Сервис заметок для finalize в dispose (последнее значение из build).
  NotesService? _notesService;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _draftDebounce?.cancel();
    // Шторка закрыта во время записи: остановить и финализировать,
    // чтобы аудио не потерялось (ТЗ 0.1: durable-сразу).
    final staged = _staged;
    if (staged != null) {
      _finishRecording(staged, popAfter: false);
    }
    if (_draftDirty) {
      unawaited(_saveDraftNow().catchError((Object e) {
        debugPrint('draft flush failed: ${e.runtimeType}');
      }));
    }
    _recorder.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ---------- Черновик ----------

  Future<void> _restoreDraft() async {
    try {
      final draft = await _drafts.load(_surfaceId);
      if (!mounted || draft == null) return;
      var text = '';
      try {
        text = PotokDocument.decode(draft.documentJson).plainText;
      } on FormatException {
        debugPrint('quick capture draft decode failed');
      }
      setState(() {
        if (_controller.text.isEmpty && text.isNotEmpty) {
          _controller.text = text;
        }
        _projectId ??= draft.projectId;
      });
    } catch (e) {
      debugPrint('draft load failed: ${e.runtimeType}');
    }
  }

  void _scheduleDraftSave() {
    _draftDirty = true;
    _draftDebounce?.cancel();
    _draftDebounce =
        Timer(const Duration(milliseconds: 500), () => _saveDraftNow());
  }

  Future<void> _saveDraftNow() async {
    _draftDirty = false;
    await _drafts.save(
      _surfaceId,
      documentJson: PotokDocument.fromPlainText(_controller.text).encode(),
      projectId: _projectId,
    );
  }

  // ---------- Сохранение ----------

  Future<Note?> _findNote(NotesService service, String id) async {
    final notes = await service.watchNotes().first;
    for (final note in notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  String _projectName(List<Project> projects) {
    for (final p in projects) {
      if (p.id == _projectId) return p.name;
    }
    return 'Без проекта';
  }

  Future<void> _saveText(NotesService service, List<Project> projects) async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Сначала введите или надиктуйте текст');
      return;
    }
    setState(() {
      _savingNote = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final id = await service.createTextNote(text);
      await _assignProject(service, id);
      _draftDebounce?.cancel();
      _draftDirty = false;
      await _drafts.clear(_surfaceId);
      if (mounted) navigator.pop();
      messenger.showSnackBar(SnackBar(
          content: Text('Заметка сохранена · ${_projectName(projects)}')));
    } catch (e) {
      debugPrint('quick capture save failed: ${e.runtimeType}');
      if (mounted) {
        setState(() {
          _savingNote = false;
          _error = 'Не удалось сохранить заметку';
        });
      }
    }
  }

  /// Перенос новой заметки в выбранный проект; сбой не отменяет создание.
  Future<void> _assignProject(NotesService service, String noteId) async {
    final projectId = _projectId;
    if (projectId == null) return;
    try {
      final note = await _findNote(service, noteId);
      if (note != null) await service.moveToProject(note, projectId);
    } catch (e) {
      debugPrint('move to project failed: ${e.runtimeType}');
    }
  }

  Future<void> _cancel() async {
    final navigator = Navigator.of(context);
    if (_controller.text.trim().isEmpty) {
      // Явная отмена пустого черновика — очищаем (FR-NOT-004).
      _draftDebounce?.cancel();
      _draftDirty = false;
      try {
        await _drafts.clear(_surfaceId);
      } catch (e) {
        debugPrint('draft clear failed: ${e.runtimeType}');
      }
    }
    if (mounted) navigator.pop();
  }

  // ---------- Запись аудио (логика WP-01 сохранена) ----------

  Future<void> _toggleRecording(NotesService service) async {
    final staged = _staged;
    if (staged != null) {
      await _finishRecording(staged, popAfter: true);
      return;
    }
    setState(() => _error = null);
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Нет доступа к микрофону');
      return;
    }
    // Slice records WAV so local ASR runs without a decode step;
    // AAC + decoder land in WP-03 (ADR-005).
    final newStaged = await service.beginAudioNote(extension: 'wav');
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
        path: newStaged.stagingPath,
      );
    } catch (e) {
      await service.abortAudioNote(newStaged);
      debugPrint('recording start failed: ${e.runtimeType}');
      if (mounted) setState(() => _error = 'Запись не началась');
      return;
    }
    _recordingStarted = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recordingStarted != null) {
        setState(
            () => _elapsed = DateTime.now().difference(_recordingStarted!));
      }
    });
    setState(() => _staged = newStaged);
  }

  Future<void> _finishRecording(
    StagedRecording staged, {
    required bool popAfter,
  }) async {
    final service = _notesService;
    if (service == null) return;
    _ticker?.cancel();
    _ticker = null;
    final duration = _recordingStarted == null
        ? Duration.zero
        : DateTime.now().difference(_recordingStarted!);
    _staged = null;
    _recordingStarted = null;
    try {
      await _recorder.stop();
      await service.finishAudioNote(
        staged,
        duration: duration,
        codec: 'pcm16-wav',
        sampleRateHz: _sampleRate,
        channels: 1,
      );
      await _assignProject(service, staged.noteId);
      if (_controller.text.trim().isEmpty) {
        _draftDebounce?.cancel();
        _draftDirty = false;
        await _drafts.clear(_surfaceId);
      }
    } catch (e) {
      await service.abortAudioNote(staged);
      debugPrint('recording finalize failed: ${e.runtimeType}');
      if (mounted) {
        setState(() => _error = 'Сохранение записи не удалось');
      }
      return;
    }
    if (popAfter && mounted) Navigator.of(context).pop();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final serviceAsync = ref.watch(notesServiceProvider);
    final service = serviceAsync.value;
    _notesService = service ?? _notesService;
    final projects =
        ref.watch(projectsProvider).value ?? const <Project>[];
    final recording = _staged != null;
    final viewInsets = MediaQuery.of(context).viewInsets;

    if (service == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(22, 22, 22, 22 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Быстрая заметка',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: c.text)),
              ),
              IconButton(
                tooltip: 'Закрыть',
                icon: Icon(Icons.close_rounded, color: c.muted),
                // Крестик НЕ удаляет черновик (FR-NOT-004).
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: _ProjectChip(
              projects: projects,
              projectId: _projectId,
              onSelected: (id) {
                setState(() => _projectId = id);
                _scheduleDraftSave();
              },
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 5,
            maxLines: 10,
            onChanged: (_) => _scheduleDraftSave(),
            style: TextStyle(fontSize: 14, height: 1.5, color: c.text),
            decoration: InputDecoration(
              hintText: 'Текст, чек-лист или запись аудио…',
              hintStyle: TextStyle(color: c.muted),
              filled: true,
              fillColor: c.surface2,
              contentPadding: const EdgeInsets.all(15),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(c.radiusSmall),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(c.radiusSmall),
                borderSide: BorderSide(color: c.accent),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '● Черновик сохраняется автоматически · проект и теги необязательны',
            style: TextStyle(fontSize: 11, color: c.decision),
          ),
          SizedBox(
            height: 28,
            child: recording
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Запись сохраняется локально… ${_elapsed.inMinutes}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 12, color: c.accent),
                    ),
                  )
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(fontSize: 12, color: c.danger),
                        ),
                      )
                    : null,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _savingNote ? null : _cancel,
                    child: const Text('Отмена'),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MicButton(
                    recording: recording,
                    onPressed:
                        _savingNote ? null : () => _toggleRecording(service),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    recording ? 'Остановить' : 'Диктовать',
                    style: TextStyle(fontSize: 10, color: c.muted),
                  ),
                ],
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed:
                        _savingNote ? null : () => _saveText(service, projects),
                    child: const Text('Готово'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectChip extends StatelessWidget {
  final List<Project> projects;
  final String? projectId;
  final ValueChanged<String?> onSelected;

  const _ProjectChip({
    required this.projects,
    required this.projectId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    Project? current;
    for (final p in projects) {
      if (p.id == projectId) {
        current = p;
        break;
      }
    }
    return PopupMenuButton<String>(
      tooltip: 'Выбрать проект',
      onSelected: (value) => onSelected(value.isEmpty ? null : value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: '',
          child: Row(
            children: [
              Icon(Icons.crop_square_rounded, size: 14, color: c.muted),
              const SizedBox(width: 8),
              const Text('Без проекта'),
            ],
          ),
        ),
        for (final project in projects)
          PopupMenuItem(
            value: project.id,
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: Color(project.colorArgb)),
                const SizedBox(width: 8),
                Flexible(child: Text(project.name)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (current != null) ...[
              Icon(Icons.circle, size: 10, color: Color(current.colorArgb)),
              const SizedBox(width: 6),
            ],
            Text(
              current?.name ?? 'Без проекта',
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down_rounded, size: 16, color: c.muted),
          ],
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool recording;
  final VoidCallback? onPressed;

  const _MicButton({required this.recording, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    return Material(
      color: c.accent,
      shape: CircleBorder(side: BorderSide(color: c.accentSoft, width: 6)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 58,
          height: 58,
          child: Icon(
            recording ? Icons.stop_rounded : Icons.mic_rounded,
            size: 26,
            color: c.accentText,
          ),
        ),
      ),
    );
  }
}
