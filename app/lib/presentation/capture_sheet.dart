import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../application/clipboard_image_reader.dart';
import '../application/drafts_service.dart';
import '../application/images_service.dart';
import '../application/notes_service.dart';
import '../application/settings_service.dart';
import '../domain/document.dart';
import '../domain/types.dart';
import '../infrastructure/asr/sherpa_recognizer_factory.dart';
import '../infrastructure/audio_recorder.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/recording_platform.dart';
import 'image_paste_intent.dart';
import 'providers.dart';
import 'snackbars.dart';
import 'tag_management.dart';
import 'theme.dart';

bool _captureOpen = false;
Completer<void>? _captureClosed;

/// Completes when an already visible capture route closes. Android launch
/// intents use this to queue multiple external requests without dropping one.
Future<void> waitForCaptureSheetClosed() =>
    _captureClosed?.future ?? Future<void>.value();

/// Quick capture (FAB, Ctrl+N): диалог на широком экране, шторка на узком.
Future<void> showCaptureSheet(
  BuildContext context, {
  Note? attachToNote,
  bool startWithAudio = false,
  String? initialText,
  String? initialProjectId,
  SourceKind sourceKind = SourceKind.keyboard,
}) async {
  if (_captureOpen) return;
  _captureOpen = true;
  final closed = Completer<void>();
  _captureClosed = closed;
  try {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: CaptureSheet(
              attachToNote: attachToNote,
              startWithAudio: startWithAudio,
              initialText: initialText,
              initialProjectId: initialProjectId,
              sourceKind: sourceKind,
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => CaptureSheet(
          attachToNote: attachToNote,
          startWithAudio: startWithAudio,
          initialText: initialText,
          initialProjectId: initialProjectId,
          sourceKind: sourceKind,
        ),
      );
    }
  } finally {
    _captureOpen = false;
    if (identical(_captureClosed, closed)) _captureClosed = null;
    if (!closed.isCompleted) closed.complete();
  }
}

/// Быстрая заметка: текст + аудио в одной поверхности (FR-NOT-001/002).
/// Черновик durable: debounce 500 мс → DraftsService('quick-capture');
/// закрытие крестиком/Esc черновик НЕ удаляет (FR-NOT-004).
class CaptureSheet extends ConsumerStatefulWidget {
  final Note? attachToNote;

  /// Ctrl+Shift+N: сразу начать запись аудио. Запись стартует только после
  /// явного разрешения микрофона; без него шторка показывает ошибку.
  final bool startWithAudio;
  final String? initialText;
  final String? initialProjectId;

  /// Origin for a text note created from this surface. Audio started here is
  /// classified as audio, except for the explicit Android widget origin.
  final SourceKind sourceKind;

  const CaptureSheet({
    super.key,
    this.attachToNote,
    this.startWithAudio = false,
    this.initialText,
    this.initialProjectId,
    this.sourceKind = SourceKind.keyboard,
  });

  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  static const _minimumFreeBytesWhileRecording = 8 * 1024 * 1024;

  String get _surfaceId => widget.attachToNote == null
      ? 'quick-capture'
      : 'audio-attachment-${widget.attachToNote!.id}';

  late final TextEditingController _controller;
  late final AudioRecorderPort _recorder;
  late final RecordingPlatformPort _recordingPlatform;

  late final DraftsService _drafts = ref.read(draftsServiceProvider);

  Timer? _draftDebounce;
  bool _draftDirty = false;
  String? _projectId;
  Note? _imageDraft;

  /// Теги, выбранные до сохранения — применяются сразу после создания
  /// заметки (тем же способом, что и `_projectId`, который тоже фиксируется
  /// в момент создания, а не постфактум).
  Set<String> _selectedTagIds = {};

  StagedRecording? _staged;
  DateTime? _recordingStarted;
  Timer? _ticker;
  StreamSubscription<RecorderLevel>? _levelSubscription;
  StreamSubscription<Uint8List>? _pcmSubscription;
  Timer? _liveTranscriptionTimer;
  final List<int> _livePcmBytes = [];
  String _liveTranscript = '';
  final _liveTranscriptScroll = ScrollController();
  String? _liveModelDir;
  bool _liveDecodeInFlight = false;
  int _liveGeneration = 0;
  Duration _elapsed = Duration.zero;
  Duration _recordingMaxDuration = const Duration(minutes: 30);
  int _recordingBitRate = 64000;
  AudioRecordingFormat _recordingFormat = AudioRecordingFormat.m4a;
  int _recordingSampleRate = 44100;
  double _level = 0;
  // growable: true — иначе removeAt/add ниже кидают UnsupportedError на
  // первом же событии уровня, и волна визуально замирает навсегда.
  final List<double> _levelHistory = List<double>.filled(36, 0, growable: true);
  int? _freeBytes;
  bool _storageCheckInFlight = false;
  bool _recordingPaused = false;
  Future<void>? _recordingFinalization;
  String? _error;
  bool _savingNote = false;
  bool _preparingAudio = false;
  late bool _autoStartAudioPending = widget.startWithAudio;

  /// Сервис заметок для finalize в dispose (последнее значение из build).
  NotesService? _notesService;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
    _projectId = widget.initialProjectId;
    _recorder = ref.read(audioRecorderFactoryProvider)();
    _recordingPlatform = ref.read(recordingPlatformProvider);
    if (widget.attachToNote == null) _restoreDraft();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _liveTranscriptionTimer?.cancel();
    unawaited(_pcmSubscription?.cancel());
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
      // Черновик пишем после финализации записи: параллельный teardown
      // недетерминирован, а порядок «сначала заметка, потом черновик»
      // согласован с _finishRecordingImpl.
      final beforeDraft = recorderOwner ?? Future<void>.value();
      unawaited(
        beforeDraft.then((_) => _saveDraftNow()).catchError((Object e) {
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
    _liveTranscriptScroll.dispose();
    super.dispose();
  }

  // ---------- Черновик ----------

  Future<void> _restoreDraft() async {
    try {
      final notes = await ref.read(notesServiceProvider.future);
      final imageDraft = await notes.findImageNoteDraft();
      final draft = await _drafts.load(_surfaceId);
      if (!mounted) return;
      if (draft != null) {
        var text = '';
        try {
          text = PotokDocument.decode(draft.documentJson).plainText;
        } on FormatException {
          debugPrint('quick capture draft decode failed');
        }
        setState(() {
          final incoming = _controller.text.trim();
          final restored = text.trim();
          if (incoming.isEmpty && restored.isNotEmpty) {
            _controller.text = restored;
          } else if (incoming.isNotEmpty &&
              restored.isNotEmpty &&
              incoming != restored) {
            // An external share must never overwrite a pre-existing durable
            // quick-capture draft. Keep both in a deterministic order.
            _controller.text = '$restored\n\n$incoming';
          }
          _projectId ??= draft.projectId;
          _imageDraft = imageDraft;
        });
      } else if (imageDraft != null) {
        setState(() {
          _imageDraft = imageDraft;
          _projectId ??= imageDraft.projectId;
        });
      }
      if ((widget.initialText ?? '').trim().isNotEmpty) {
        _draftDirty = true;
        await _saveDraftNow();
      }
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

  /// Применяет теги, выбранные до сохранения. Лучшее усилие — сбой не
  /// должен мешать самой заметке сохраниться (она уже создана к этому
  /// моменту), поэтому ошибка только логируется.
  Future<void> _applySelectedTags(String noteId) async {
    if (_selectedTagIds.isEmpty) return;
    try {
      final tagsService = await ref.read(tagsServiceProvider.future);
      for (final tagId in _selectedTagIds) {
        await tagsService.assignTag(noteId, tagId);
      }
    } catch (e) {
      debugPrint('capture tag assign failed: ${e.runtimeType}');
    }
  }

  Future<void> _saveText(NotesService service, List<Project> projects) async {
    final text = _controller.text.trim();
    final imageDraft = _imageDraft;
    if (text.isEmpty && imageDraft == null) {
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
      final projectId = _projectId;
      if (imageDraft == null) {
        final noteId = await service.createTextNote(
          text,
          projectId: projectId,
          sourceKind: widget.sourceKind,
        );
        await _applySelectedTags(noteId);
      } else {
        final imageDocument = PotokDocument.decode(imageDraft.documentJson);
        var document = PotokDocument.fromPlainText(text);
        for (final op in imageDocument.deltaOps) {
          final insert = op['insert'];
          if (insert is! Map<String, Object?>) continue;
          final uri = insert['image'];
          if (uri is! String || !uri.startsWith('asset://')) continue;
          final attributes = op['attributes'];
          final alt = attributes is Map<String, Object?>
              ? attributes['alt'] as String?
              : null;
          document = document.appendImage(
            uri.substring('asset://'.length),
            alt: alt ?? 'Изображение',
          );
        }
        await service.publishImageNoteDraft(
          imageDraft,
          document,
          projectId: projectId,
        );
        await _applySelectedTags(imageDraft.id);
        _imageDraft = null;
      }
      _draftDebounce?.cancel();
      _draftDirty = false;
      await _drafts.clear(_surfaceId);
      if (!mounted) return;
      final message =
          'Заметка сохранена · ${_projectName(projects, projectId)}';
      final snackBar = compactSnackBar(context, message);
      navigator.pop();
      messenger.showSnackBar(snackBar);
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
      await _stopLivePreview();
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
    final imageDraft = _imageDraft;
    if (imageDraft != null) {
      final images = await ref.read(imagesServiceProvider.future);
      final notes = await ref.read(notesServiceProvider.future);
      await images.discardDraftImages(imageDraft.id);
      await notes.discardImageNoteDraft(imageDraft);
      _imageDraft = null;
    }
    if (mounted) navigator.pop();
  }

  Future<Note> _ensureImageDraft(NotesService notes) async {
    final existing = _imageDraft;
    if (existing != null) return existing;
    final created = await notes.beginImageNoteDraft(
      projectId: _projectId,
      sourceKind: widget.sourceKind,
    );
    if (mounted) setState(() => _imageDraft = created);
    return created;
  }

  Future<void> _attachPickedImage(NotesService notes) async {
    const typeGroup = XTypeGroup(
      label: 'Изображения',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (picked == null || !mounted) return;
      final draft = await _ensureImageDraft(notes);
      final images = await ref.read(imagesServiceProvider.future);
      final asset = await images.attachImage(draft, picked.path);
      final alt = p.basenameWithoutExtension(picked.path).trim();
      await _appendDraftImage(
        notes,
        draft,
        asset.id,
        alt.isEmpty ? 'Изображение' : alt,
      );
    } on ImageAttachException catch (error) {
      messenger.showSnackBar(PotokSnackBar(content: Text(error.message)));
    } catch (error) {
      debugPrint('capture image attach failed: ${error.runtimeType}');
      messenger.showSnackBar(
        PotokSnackBar(content: const Text('Не удалось прикрепить фото')),
      );
    }
  }

  Future<void> _appendDraftImage(
    NotesService notes,
    Note draft,
    String assetId,
    String alt,
  ) async {
    final document = PotokDocument.decode(
      draft.documentJson,
    ).appendImage(assetId, alt: alt);
    await notes.updateImageNoteDraft(draft, document, projectId: _projectId);
    final fresh = await notes.getNote(draft.id);
    if (fresh != null && mounted) setState(() => _imageDraft = fresh);
  }

  Future<void> _pasteIntoCapture(NotesService notes) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final image = await ref.read(clipboardImageReaderProvider).readImage();
      if (image != null) {
        final draft = await _ensureImageDraft(notes);
        final images = await ref.read(imagesServiceProvider.future);
        final asset = await images.attachImageBytes(
          draft,
          image.bytes,
          extension: image.extension,
        );
        await _appendDraftImage(
          notes,
          draft,
          asset.id,
          'Изображение из буфера',
        );
        return;
      }
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty || !mounted) return;
      final selection = _controller.selection;
      final start = selection.isValid
          ? selection.start
          : _controller.text.length;
      final end = selection.isValid ? selection.end : start;
      _controller.value = TextEditingValue(
        text: _controller.text.replaceRange(start, end, text),
        selection: TextSelection.collapsed(offset: start + text.length),
      );
      _scheduleDraftSave();
      setState(() {});
    } on ImageAttachException catch (error) {
      messenger.showSnackBar(PotokSnackBar(content: Text(error.message)));
    } on ClipboardImageReadException catch (error) {
      messenger.showSnackBar(PotokSnackBar(content: Text(error.message)));
    } catch (error) {
      debugPrint('capture clipboard paste failed: ${error.runtimeType}');
      messenger.showSnackBar(
        PotokSnackBar(content: const Text('Не удалось вставить изображение')),
      );
    }
  }

  // ---------- Запись аудио (логика WP-01 сохранена) ----------

  Future<void> _toggleRecording(NotesService service) async {
    if (_recordingFinalization != null || _preparingAudio) return;
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
    final settings = ref.read(settingsServiceProvider);
    final storedBitRate = int.tryParse(
      await settings.get(SettingsService.audioBitRateKey) ?? '',
    );
    final storedMaxMinutes = int.tryParse(
      await settings.get(SettingsService.audioMaxMinutesKey) ?? '',
    );
    if (mounted) setState(() => _preparingAudio = true);
    String? activeModelDir;
    try {
      activeModelDir = await ref.read(activeAsrModelDirectoryProvider.future);
    } catch (error) {
      debugPrint('ASR model bootstrap failed: ${error.runtimeType}');
      if (mounted) {
        setState(() {
          _error =
              'Модель распознавания недоступна — аудио сохранится без расшифровки';
        });
      }
    } finally {
      if (mounted) setState(() => _preparingAudio = false);
    }
    _recordingFormat = activeModelDir == null
        ? AudioRecordingFormat.m4a
        : AudioRecordingFormat.wavPcm16;
    _recordingSampleRate = _recordingFormat == AudioRecordingFormat.wavPcm16
        ? 16000
        : 44100;
    _recordingBitRate = const {48000, 64000, 96000}.contains(storedBitRate)
        ? storedBitRate!
        : 64000;
    _recordingMaxDuration = Duration(
      minutes: const {10, 30, 60, 120}.contains(storedMaxMinutes)
          ? storedMaxMinutes!
          : 30,
    );
    final extension = _recordingFormat == AudioRecordingFormat.wavPcm16
        ? 'wav'
        : 'm4a';
    late final StagedRecording newStaged;
    try {
      newStaged = widget.attachToNote == null
          ? await service.beginAudioNote(
              extension: extension,
              projectId: _projectId,
              sourceKind: widget.sourceKind == SourceKind.widget
                  ? SourceKind.widget
                  : SourceKind.audio,
            )
          : await service.beginAudioAttachment(
              widget.attachToNote!,
              extension: extension,
            );
    } catch (error) {
      debugPrint('recording staging failed: ${error.runtimeType}');
      if (mounted) setState(() => _error = 'Заметка изменилась — повторите');
      return;
    }
    if (widget.attachToNote == null) {
      await _applySelectedTags(newStaged.noteId);
    }
    try {
      final selectedInputId = await settings.get(
        SettingsService.audioInputDeviceKey,
      );
      final expectedBytes = _recordingFormat == AudioRecordingFormat.wavPcm16
          ? _recordingSampleRate * 2 * _recordingMaxDuration.inSeconds + 44
          : (_recordingBitRate / 8 * _recordingMaxDuration.inSeconds).ceil();
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
      await _recorder.start(
        newStaged.stagingPath,
        format: _recordingFormat,
        bitRate: _recordingBitRate,
        inputDeviceId: selectedInputId,
      );
      if (activeModelDir != null) _startLivePreview(activeModelDir);
    } on _InsufficientStorageException {
      await service.abortAudioNote(newStaged);
      if (mounted) {
        setState(() => _error = 'Недостаточно места для начала записи');
      }
      return;
    } on AudioInputDeviceUnavailableException {
      await _recordingPlatform.setRecordingActive(false);
      await service.abortAudioNote(newStaged);
      if (mounted) {
        setState(
          () => _error = 'Выбранный микрофон недоступен — измените настройку',
        );
      }
      return;
    } on AudioRecorderStartException catch (error) {
      await _recordingPlatform.setRecordingActive(false);
      await service.abortAudioNote(newStaged);
      if (mounted) {
        setState(() {
          _error = switch (error.failure) {
            AudioRecorderStartFailure.permission =>
              'Windows запретил доступ к микрофону — проверьте параметры конфиденциальности',
            AudioRecorderStartFailure.device =>
              'Микрофон отключён или занят — выберите другое устройство',
            AudioRecorderStartFailure.unsupported =>
              'Драйвер микрофона не поддерживает формат записи',
            AudioRecorderStartFailure.platform =>
              'Windows не смог начать запись — переподключите микрофон',
          };
        });
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
    _liveTranscript = '';
    _levelHistory.fillRange(0, _levelHistory.length, 0);
    _levelSubscription = _recorder.levels().listen((value) {
      if (!mounted) return;
      setState(() {
        _level = value.normalized;
        _levelHistory
          ..removeAt(0)
          ..add(value.normalized);
      });
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
    final liveTranscript = _liveTranscript;
    final duration = _elapsed;
    _staged = null;
    _recordingStarted = null;
    _recordingPaused = false;
    _ticker?.cancel();
    _ticker = null;
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    await _stopLivePreview();
    try {
      await _recorder.stop();
      await _recordingPlatform.setRecordingActive(false);
      await service.finishAudioNote(
        staged,
        duration: duration,
        codec: _recordingFormat == AudioRecordingFormat.wavPcm16
            ? 'pcm16-wav'
            : 'aac-lc',
        sampleRateHz: _recordingSampleRate,
        channels: 1,
        comment: widget.attachToNote == null ? comment : null,
      );
      // The live decoder can preserve a short spoken command that the final
      // full-file pass later misrecognizes. Both paths use one deduplicating
      // coordinator and only match already existing entities.
      await ref.read(processVoiceClassificationProvider)(
        staged.noteId,
        liveTranscript,
      );
      await _enqueueTranscriptionIfModelActive(staged, liveTranscript);
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

  Future<void> _enqueueTranscriptionIfModelActive(
    StagedRecording staged,
    String liveTranscript,
  ) async {
    try {
      await ref.read(automaticTranscriptionEnqueueProvider)(
        staged.noteId,
        staged.assetId,
        liveTranscript,
      );
    } catch (error) {
      // Audio is already ready and remains available for explicit retry.
      debugPrint(
        'automatic transcription enqueue failed: ${error.runtimeType}',
      );
    }
  }

  Future<void> _finalizeDetached(
    StagedRecording staged, {
    required NotesService? service,
    required Duration duration,
    required String comment,
  }) async {
    if (service == null) {
      // Сервис недоступен в момент уничтожения route ОС — заметка из этой
      // записи не будет создана. Фиксируем потерю явно, не молча.
      debugPrint(
        'detached finalize skipped: notes service unavailable, recording lost',
      );
      await _stopLivePreview();
      await _recorder.cancel();
      return;
    }
    try {
      await _stopLivePreview();
      await _recorder.stop();
      await _recordingPlatform.setRecordingActive(false);
      await service.finishAudioNote(
        staged,
        duration: duration,
        codec: _recordingFormat == AudioRecordingFormat.wavPcm16
            ? 'pcm16-wav'
            : 'aac-lc',
        sampleRateHz: _recordingSampleRate,
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

  void _startLivePreview(String modelDir) {
    _liveTranscriptionTimer?.cancel();
    unawaited(_pcmSubscription?.cancel());
    _liveModelDir = modelDir;
    _livePcmBytes.clear();
    _liveTranscript = '';
    final generation = ++_liveGeneration;
    _pcmSubscription = _recorder.pcm16Chunks().listen((chunk) {
      if (generation == _liveGeneration && !_recordingPaused) {
        _livePcmBytes.addAll(chunk);
      }
    });
    _liveTranscriptionTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_decodeLiveChunk(generation)),
    );
  }

  Future<void> _decodeLiveChunk(int generation) async {
    final modelDir = _liveModelDir;
    if (modelDir == null ||
        generation != _liveGeneration ||
        _liveDecodeInFlight ||
        _livePcmBytes.length < 32000) {
      return;
    }
    final bytes = Uint8List.fromList(_livePcmBytes);
    _livePcmBytes.clear();
    final sampleCount = bytes.length ~/ 2;
    final samples = Float32List(sampleCount);
    final data = ByteData.sublistView(bytes);
    for (var index = 0; index < sampleCount; index++) {
      samples[index] = data.getInt16(index * 2, Endian.little) / 32768.0;
    }
    _liveDecodeInFlight = true;
    try {
      final result = await createSherpaRecognizer(
        modelDir,
      ).transcribeSamples(samples);
      final text = result.text.trim();
      if (text.isNotEmpty && mounted && generation == _liveGeneration) {
        setState(() {
          _liveTranscript = _liveTranscript.isEmpty
              ? text
              : '$_liveTranscript $text';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_liveTranscriptScroll.hasClients) return;
          unawaited(
            _liveTranscriptScroll.animateTo(
              _liveTranscriptScroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            ),
          );
        });
      }
    } catch (error) {
      // Preview is best-effort. The durable full-file queue still runs after
      // stop, and diagnostics must not include recognized content or paths.
      debugPrint('live transcription failed: ${error.runtimeType}');
    } finally {
      _liveDecodeInFlight = false;
    }
  }

  Future<void> _stopLivePreview() async {
    _liveTranscriptionTimer?.cancel();
    _liveTranscriptionTimer = null;
    await _pcmSubscription?.cancel();
    _pcmSubscription = null;
    _livePcmBytes.clear();
    _liveModelDir = null;
    _liveGeneration++;
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
          PotokSnackBar(
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
    final effectiveProjectId = _projectId;
    final recording = _staged != null;
    final showTranscriptionProgress =
        ref.watch(showTranscriptionProgressProvider).value ?? true;
    final viewInsets = MediaQuery.of(context).viewInsets;
    var imageCount = 0;
    final imageDraft = _imageDraft;
    if (imageDraft != null) {
      try {
        imageCount = PotokDocument.decode(
          imageDraft.documentJson,
        ).managedAssetIds.length;
      } on FormatException {
        imageCount = 0;
      }
    }

    if (service == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Ctrl+Shift+N: автостарт записи после первого кадра с готовым сервисом.
    // Проверка разрешения микрофона и ошибки — внутри _toggleRecording.
    if (_autoStartAudioPending) {
      _autoStartAudioPending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _staged != null || _savingNote) return;
        unawaited(_toggleRecording(service));
      });
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
                // Правшам удобнее, когда выбор проекта под большим пальцем
                // у правого края экрана на Android.
                alignment: Platform.isAndroid
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TagSelectorChip(
                      projectId: effectiveProjectId,
                      selectedTagIds: _selectedTagIds,
                      onChanged: (ids) => setState(() => _selectedTagIds = ids),
                    ),
                    const SizedBox(width: 8),
                    _ProjectChip(
                      projects: projects,
                      projectId: effectiveProjectId,
                      onSelected: (id) {
                        setState(() => _projectId = id);
                        _scheduleDraftSave();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.keyV, control: true):
                      PasteWithImagesIntent(),
                },
                child: Actions(
                  actions: {
                    PasteWithImagesIntent:
                        CallbackAction<PasteWithImagesIntent>(
                          onInvoke: (_) {
                            unawaited(_pasteIntoCapture(service));
                            return null;
                          },
                        ),
                  },
                  child: TextField(
                    controller: _controller,
                    autofocus: false,
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
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Platform.isAndroid
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('capture-attach-photo'),
                  onPressed: _savingNote
                      ? null
                      : () => _attachPickedImage(service),
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: Text(
                    imageCount == 0
                        ? 'Прикрепить фото'
                        : 'Прикрепить фото · $imageCount',
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
                  : '● Черновик сохраняется автоматически · проект и теги необязательны',
              style: TextStyle(fontSize: 11, color: c.decision),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: recording
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Запись сохраняется локально… ${_elapsed.inMinutes}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')} · ${_formatFreeBytes(_freeBytes)}',
                            style: TextStyle(fontSize: 12, color: c.accent),
                          ),
                          if (_liveModelDir != null) ...[
                            const SizedBox(height: 6),
                            if (showTranscriptionProgress) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  key: const ValueKey(
                                    'live-transcription-progress',
                                  ),
                                  value: _liveDecodeInFlight
                                      ? null
                                      : (_livePcmBytes.length / 128000).clamp(
                                          0.0,
                                          1.0,
                                        ),
                                  minHeight: 3,
                                ),
                              ),
                              const SizedBox(height: 5),
                            ],
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 64),
                              child: Scrollbar(
                                controller: _liveTranscriptScroll,
                                child: SingleChildScrollView(
                                  controller: _liveTranscriptScroll,
                                  child: Text(
                                    _liveTranscript.isEmpty
                                        ? 'Распознавание появится через несколько секунд…'
                                        : _liveTranscript,
                                    key: const ValueKey(
                                      'live-transcript-preview',
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      color: c.text,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _error!,
                              style: TextStyle(fontSize: 12, color: c.danger),
                            ),
                          ],
                        ],
                      ),
                    )
                  : _preparingAudio
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Подготовка офлайн-модели…',
                              style: TextStyle(fontSize: 12, color: c.muted),
                            ),
                          ),
                        ],
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
                      onPressed: _savingNote || _preparingAudio
                          ? null
                          : () => _toggleRecording(service),
                    ),
                    if (recording) ...[
                      const SizedBox(height: 4),
                      Semantics(
                        label: 'Уровень сигнала записи',
                        value: '${(_level * 100).round()}%',
                        child: SizedBox(
                          key: const ValueKey('recording-level'),
                          width: 92,
                          height: 22,
                          child: CustomPaint(
                            painter: _AudioWaveformPainter(
                              levels: List<double>.of(_levelHistory),
                              color: c.accent,
                              idleColor: c.line,
                            ),
                          ),
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
                            onPressed: _savingNote
                                ? null
                                : recording
                                ? () =>
                                      _finishRecording(_staged!, popAfter: true)
                                : () => _saveText(service, projects),
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

class _AudioWaveformPainter extends CustomPainter {
  final List<double> levels;
  final Color color;
  final Color idleColor;

  const _AudioWaveformPainter({
    required this.levels,
    required this.color,
    required this.idleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final baseline = Paint()
      ..color = idleColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), baseline);
    if (levels.isEmpty || size.width <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final step = size.width / levels.length;
    for (var index = 0; index < levels.length; index++) {
      final normalized = levels[index].clamp(0.0, 1.0);
      final eased = normalized * normalized;
      final halfHeight = 1.5 + eased * (centerY - 2);
      final x = step * index + step / 2;
      canvas.drawLine(
        Offset(x, centerY - halfHeight),
        Offset(x, centerY + halfHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) =>
      oldDelegate.levels != levels ||
      oldDelegate.color != color ||
      oldDelegate.idleColor != idleColor;
}

class _InsufficientStorageException implements Exception {
  const _InsufficientStorageException();
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

/// Мультивыбор тегов до сохранения заметки — теги ещё не привязаны ни к
/// какой заметке (её пока не существует), поэтому выбор живёт локально в
/// состоянии шторки и применяется сразу после создания (см.
/// `_applySelectedTags`), тем же способом, что и выбор проекта.
class _TagSelectorChip extends ConsumerWidget {
  final String? projectId;
  final Set<String> selectedTagIds;
  final ValueChanged<Set<String>> onChanged;

  const _TagSelectorChip({
    required this.projectId,
    required this.selectedTagIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    return InkWell(
      key: const ValueKey('capture-tag-selector'),
      borderRadius: BorderRadius.circular(999),
      onTap: () async {
        final result = await showDialog<Set<String>>(
          context: context,
          builder: (dialogContext) => _CaptureTagPickerDialog(
            projectId: projectId,
            initialSelected: selectedTagIds,
          ),
        );
        if (result != null) onChanged(result);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_outline_rounded, size: 14, color: c.muted),
            const SizedBox(width: 6),
            Text(
              selectedTagIds.isEmpty
                  ? 'Теги'
                  : 'Теги · ${selectedTagIds.length}',
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

class _CaptureTagPickerDialog extends ConsumerStatefulWidget {
  final String? projectId;
  final Set<String> initialSelected;

  const _CaptureTagPickerDialog({
    required this.projectId,
    required this.initialSelected,
  });

  @override
  ConsumerState<_CaptureTagPickerDialog> createState() =>
      _CaptureTagPickerDialogState();
}

class _CaptureTagPickerDialogState
    extends ConsumerState<_CaptureTagPickerDialog> {
  late final Set<String> _selected = Set.of(widget.initialSelected);

  Future<void> _createAndSelect() async {
    final tagId = await showTagEditorDialog(
      context,
      ref,
      initialProjectId: widget.projectId,
    );
    if (tagId == null || !mounted) return;
    setState(() => _selected.add(tagId));
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final tags =
        ref.watch(availableTagsProvider(widget.projectId)).value ??
        const <Tag>[];
    return AlertDialog(
      title: const Text('Теги заметки'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final tag in tags)
                    CheckboxListTile(
                      key: ValueKey('capture-tag-picker-${tag.id}'),
                      dense: true,
                      value: _selected.contains(tag.id),
                      onChanged: (value) => setState(() {
                        if (value ?? false) {
                          _selected.add(tag.id);
                        } else {
                          _selected.remove(tag.id);
                        }
                      }),
                      secondary: Icon(
                        Icons.circle,
                        size: 12,
                        color: Color(tag.colorArgb),
                      ),
                      title: Text(tag.name),
                    ),
                  if (tags.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Тегов пока нет',
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              dense: true,
              leading: const Icon(Icons.add_rounded, size: 18),
              title: const Text('Создать тег…'),
              onTap: _createAndSelect,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('capture-tag-picker-done'),
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Готово'),
        ),
      ],
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
