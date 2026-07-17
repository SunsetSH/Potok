import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../application/drafts_service.dart';
import '../application/notes_service.dart';
import '../application/settings_service.dart';
import '../domain/document.dart';
import '../domain/types.dart';
import '../infrastructure/audio_recorder.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/recording_platform.dart';
import 'providers.dart';
import 'theme.dart';

bool _captureOpen = false;

/// Quick capture (FAB, Ctrl+N): диалог на широком экране, шторка на узком.
Future<void> showCaptureSheet(
  BuildContext context, {
  String? sessionId,
  Note? attachToNote,
}) async {
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
            child: CaptureSheet(
              sessionId: sessionId,
              attachToNote: attachToNote,
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => CaptureSheet(
          sessionId: sessionId,
          attachToNote: attachToNote,
        ),
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
  final String? sessionId;
  final Note? attachToNote;

  const CaptureSheet({super.key, this.sessionId, this.attachToNote});

  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  static const _sampleRate = 44100;
  static const _minimumFreeBytesWhileRecording = 8 * 1024 * 1024;

  String get _surfaceId => widget.sessionId == null
      ? widget.attachToNote == null
            ? 'quick-capture'
            : 'audio-attachment-${widget.attachToNote!.id}'
      : 'session-capture-${widget.sessionId}';

  final _controller = TextEditingController();
  late final AudioRecorderPort _recorder;
  late final RecordingPlatformPort _recordingPlatform;

  late final DraftsService _drafts = ref.read(draftsServiceProvider);

  Timer? _draftDebounce;
  bool _draftDirty = false;
  String? _projectId;

  StagedRecording? _staged;
  DateTime? _recordingStarted;
  Timer? _ticker;
  StreamSubscription<RecorderLevel>? _levelSubscription;
  Duration _elapsed = Duration.zero;
  Duration _recordingMaxDuration = const Duration(minutes: 30);
  int _recordingBitRate = 64000;
  double _level = 0;
  int? _freeBytes;
  bool _storageCheckInFlight = false;
  bool _recordingPaused = false;
  Future<void>? _recordingFinalization;
  String? _error;
  bool _savingNote = false;

  /// Сервис заметок для finalize в dispose (последнее значение из build).
  NotesService? _notesService;

  @override
  void initState() {
    super.initState();
    _recorder = ref.read(audioRecorderFactoryProvider)();
    _recordingPlatform = ref.read(recordingPlatformProvider);
    if (widget.attachToNote == null) _restoreDraft();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_levelSubscription?.cancel());
    _draftDebounce?.cancel();
    // PopScope не даёт обычно закрыть шторку во время записи.
    // Эта ветка — страховка для уничтожения route самой ОС.
    final staged = _staged;
    final pendingFinalization = _recordingFinalization;
    Future<void>? recorderOwner = pendingFinalization;
    if (staged != null && pendingFinalization == null) {
      _staged = null;
      recorderOwner = _finalizeDetached(
        staged,
        service: _notesService,
        duration: _elapsed,
        comment: _controller.text,
      );
    }
    if (_draftDirty && widget.attachToNote == null) {
      unawaited(
        _saveDraftNow().catchError((Object e) {
          debugPrint('draft flush failed: ${e.runtimeType}');
        }),
      );
    }
    if (recorderOwner == null) {
      unawaited(_recorder.dispose());
    } else {
      unawaited(recorderOwner.whenComplete(_recorder.dispose));
    }
    unawaited(_recordingPlatform.setRecordingActive(false));
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
    _draftDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _saveDraftNow(),
    );
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

  String _projectName(List<Project> projects, String? projectId) {
    for (final p in projects) {
      if (p.id == projectId) return p.name;
    }
    return 'Без проекта';
  }

  Future<void> _saveText(
    NotesService service,
    List<Project> projects,
    Session? session,
  ) async {
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
      final projectId = session?.projectId ?? _projectId;
      await service.createTextNote(
        text,
        projectId: projectId,
        sessionId: session?.id,
      );
      _draftDebounce?.cancel();
      _draftDirty = false;
      await _drafts.clear(_surfaceId);
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Заметка сохранена · ${_projectName(projects, projectId)}',
          ),
        ),
      );
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

  Future<void> _cancel() async {
    final navigator = Navigator.of(context);
    final staged = _staged;
    if (staged != null) {
      _ticker?.cancel();
      await _levelSubscription?.cancel();
      await _recorder.cancel();
      await _recordingPlatform.setRecordingActive(false);
      await _notesService?.abortAudioNote(staged);
      _staged = null;
      _recordingStarted = null;
    }
    if (widget.attachToNote == null && _controller.text.trim().isEmpty) {
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

  Future<void> _toggleRecording(NotesService service, Session? session) async {
    if (_recordingFinalization != null) return;
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
    late final StagedRecording newStaged;
    try {
      newStaged = widget.attachToNote == null
          ? await service.beginAudioNote(
              extension: 'm4a',
              projectId: session?.projectId ?? _projectId,
              sessionId: session?.id,
            )
          : await service.beginAudioAttachment(widget.attachToNote!);
    } catch (error) {
      debugPrint('recording staging failed: ${error.runtimeType}');
      if (mounted) setState(() => _error = 'Заметка изменилась — повторите');
      return;
    }
    try {
      final settings = ref.read(settingsServiceProvider);
      final storedBitRate = int.tryParse(
        await settings.get(SettingsService.audioBitRateKey) ?? '',
      );
      final storedMaxMinutes = int.tryParse(
        await settings.get(SettingsService.audioMaxMinutesKey) ?? '',
      );
      _recordingBitRate = const {48000, 64000, 96000}.contains(storedBitRate)
          ? storedBitRate!
          : 64000;
      _recordingMaxDuration = Duration(
        minutes: const {10, 30, 60, 120}.contains(storedMaxMinutes)
            ? storedMaxMinutes!
            : 30,
      );
      final expectedBytes =
          (_recordingBitRate / 8 * _recordingMaxDuration.inSeconds).ceil();
      final minimumFreeBytesToStart =
          expectedBytes + _minimumFreeBytesWhileRecording;
      final available = await _recordingPlatform.freeBytes(
        p.dirname(newStaged.stagingPath),
      );
      if (available != null && available < minimumFreeBytesToStart) {
        throw const _InsufficientStorageException();
      }
      _freeBytes = available;
      await _recordingPlatform.setRecordingActive(true);
      await _recorder.startM4a(
        newStaged.stagingPath,
        bitRate: _recordingBitRate,
      );
    } on _InsufficientStorageException {
      await service.abortAudioNote(newStaged);
      if (mounted) {
        setState(() => _error = 'Недостаточно места для начала записи');
      }
      return;
    } catch (e) {
      await _recordingPlatform.setRecordingActive(false);
      await service.abortAudioNote(newStaged);
      debugPrint('recording start failed: ${e.runtimeType}');
      if (mounted) setState(() => _error = 'Запись не началась');
      return;
    }
    _recordingStarted = DateTime.now();
    _elapsed = Duration.zero;
    _recordingPaused = false;
    _levelSubscription = _recorder.levels().listen((value) {
      if (mounted) setState(() => _level = value.normalized);
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recordingStarted != null) {
        if (!_recordingPaused) {
          setState(() => _elapsed += const Duration(seconds: 1));
        }
        if (_elapsed >= _recordingMaxDuration && _staged != null) {
          unawaited(_finishRecording(_staged!, popAfter: true));
        } else if (_elapsed.inSeconds % 5 == 0 && _staged != null) {
          unawaited(_checkStorageWhileRecording(_staged!));
        }
      }
    });
    setState(() => _staged = newStaged);
  }

  Future<void> _finishRecording(
    StagedRecording staged, {
    required bool popAfter,
  }) {
    final existing = _recordingFinalization;
    if (existing != null) return existing;
    late final Future<void> tracked;
    tracked = _finishRecordingImpl(staged, popAfter: popAfter).whenComplete(() {
      if (identical(_recordingFinalization, tracked)) {
        _recordingFinalization = null;
      }
    });
    _recordingFinalization = tracked;
    return tracked;
  }

  Future<void> _finishRecordingImpl(
    StagedRecording staged, {
    required bool popAfter,
  }) async {
    final service = _notesService;
    if (service == null) return;
    final comment = _controller.text;
    final duration = _elapsed;
    _staged = null;
    _recordingStarted = null;
    _recordingPaused = false;
    _ticker?.cancel();
    _ticker = null;
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    try {
      await _recorder.stop();
      await _recordingPlatform.setRecordingActive(false);
      await service.finishAudioNote(
        staged,
        duration: duration,
        codec: 'aac-lc',
        sampleRateHz: _sampleRate,
        channels: 1,
        comment: widget.attachToNote == null ? comment : null,
      );
      if (widget.attachToNote == null && _controller.text.trim().isEmpty) {
        _draftDebounce?.cancel();
        _draftDirty = false;
        await _drafts.clear(_surfaceId);
      }
    } catch (e) {
      await _recordingPlatform.setRecordingActive(false);
      await service.abortAudioNote(staged);
      debugPrint('recording finalize failed: ${e.runtimeType}');
      if (mounted) {
        setState(() => _error = 'Сохранение записи не удалось');
      }
      return;
    }
    if (popAfter && mounted) Navigator.of(context).pop();
  }

  Future<void> _finalizeDetached(
    StagedRecording staged, {
    required NotesService? service,
    required Duration duration,
    required String comment,
  }) async {
    if (service == null) {
      await _recorder.cancel();
      return;
    }
    try {
      await _recorder.stop();
      await _recordingPlatform.setRecordingActive(false);
      await service.finishAudioNote(
        staged,
        duration: duration,
        codec: 'aac-lc',
        sampleRateHz: _sampleRate,
        channels: 1,
        comment: widget.attachToNote == null ? comment : null,
      );
    } catch (e) {
      await _recordingPlatform.setRecordingActive(false);
      await service.abortAudioNote(staged);
      debugPrint('recording recovery finalize failed: ${e.runtimeType}');
    }
  }

  Future<void> _requestClose() async {
    final staged = _staged;
    if (staged != null) {
      await _finishRecording(staged, popAfter: true);
    } else if (mounted && _recordingFinalization == null) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _checkStorageWhileRecording(StagedRecording staged) async {
    if (_storageCheckInFlight || _staged?.assetId != staged.assetId) return;
    _storageCheckInFlight = true;
    try {
      final available = await _recordingPlatform.freeBytes(
        p.dirname(staged.stagingPath),
      );
      if (!mounted || _staged?.assetId != staged.assetId) return;
      setState(() => _freeBytes = available);
      if (available != null && available < _minimumFreeBytesWhileRecording) {
        final messenger = ScaffoldMessenger.of(context);
        await _finishRecording(staged, popAfter: true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Мало места: пригодная часть записи сохранена'),
          ),
        );
      }
    } catch (e) {
      debugPrint('free space check failed: ${e.runtimeType}');
    } finally {
      _storageCheckInFlight = false;
    }
  }

  String _formatFreeBytes(int? value) {
    if (value == null) return 'место: нет данных';
    final gib = value / (1024 * 1024 * 1024);
    if (gib >= 1) return 'свободно ${gib.toStringAsFixed(1)} ГБ';
    final mib = value / (1024 * 1024);
    return 'свободно ${mib.toStringAsFixed(0)} МБ';
  }

  Future<void> _toggleRecordingPause() async {
    if (_recordingPaused) {
      await _recorder.resume();
    } else {
      await _recorder.pause();
    }
    if (mounted) setState(() => _recordingPaused = !_recordingPaused);
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final serviceAsync = ref.watch(notesServiceProvider);
    final service = serviceAsync.value;
    _notesService = service ?? _notesService;
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    final currentSession = ref.watch(currentSessionProvider).value;
    final captureSession =
        widget.sessionId != null &&
            currentSession?.id == widget.sessionId &&
            currentSession?.state == SessionState.active
        ? currentSession
        : null;
    final requestedSessionUnavailable =
        widget.attachToNote == null &&
        widget.sessionId != null &&
        captureSession == null;
    final effectiveProjectId = captureSession?.projectId ?? _projectId;
    final recording = _staged != null;
    final viewInsets = MediaQuery.of(context).viewInsets;

    if (service == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope<void>(
      canPop: !recording && _recordingFinalization == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 22, 22, 22 + viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                  widget.attachToNote == null
                      ? 'Быстрая заметка'
                      : 'Добавить аудио',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  icon: Icon(Icons.close_rounded, color: c.muted),
                  // Крестик НЕ удаляет черновик (FR-NOT-004).
                  onPressed: _requestClose,
                ),
              ],
            ),
            const SizedBox(height: 12),
          if (widget.attachToNote == null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: _ProjectChip(
                projects: projects,
                projectId: effectiveProjectId,
                enabled: captureSession == null,
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
                hintText:
                    'Текст, чек-лист или запись аудио…',
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
          ] else
            Text(
              'Запись будет добавлена к текущей заметке. Её текст не изменится.',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
            const SizedBox(height: 8),
            Text(
            widget.attachToNote != null
                ? '● К заметке можно добавить несколько независимых записей'
                : captureSession == null
                  ? '● Черновик сохраняется автоматически · проект и теги необязательны'
                  : '● Заметка войдёт в сессию «${captureSession.title}»',
              style: TextStyle(fontSize: 11, color: c.decision),
            ),
            SizedBox(
              height: 28,
              child: recording
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Запись сохраняется локально… ${_elapsed.inMinutes}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')} · ${_formatFreeBytes(_freeBytes)}',
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
                      onPressed: _savingNote || requestedSessionUnavailable
                          ? null
                          : () => _toggleRecording(service, captureSession),
                    ),
                    if (recording) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 64,
                        child: LinearProgressIndicator(
                          key: const ValueKey('recording-level'),
                          value: _level,
                          minHeight: 3,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('recording-pause-resume'),
                        tooltip: _recordingPaused
                            ? 'Продолжить запись'
                            : 'Приостановить запись',
                        onPressed: _toggleRecordingPause,
                        icon: Icon(
                          _recordingPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      recording ? 'Остановить' : 'Диктовать',
                      style: TextStyle(fontSize: 10, color: c.muted),
                    ),
                  ],
                ),
              Expanded(
                child: widget.attachToNote == null
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed:
                              _savingNote || requestedSessionUnavailable
                              ? null
                              : () => _saveText(
                                  service,
                                  projects,
                                  captureSession,
                                ),
                          child: const Text('Готово'),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InsufficientStorageException implements Exception {
  const _InsufficientStorageException();
}

class _ProjectChip extends StatelessWidget {
  final List<Project> projects;
  final String? projectId;
  final bool enabled;
  final ValueChanged<String?> onSelected;

  const _ProjectChip({
    required this.projects,
    required this.projectId,
    this.enabled = true,
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
      enabled: enabled,
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
        key: const ValueKey('recording-mic'),
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
