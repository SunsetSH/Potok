import 'dart:async';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../application/notes_service.dart';

Future<void> showCaptureSheet(BuildContext context, NotesService service) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => CaptureSheet(service: service),
  );
}

/// Quick capture: text + audio in one surface (FR-NOT-001/002).
class CaptureSheet extends StatefulWidget {
  final NotesService service;
  const CaptureSheet({super.key, required this.service});

  @override
  State<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<CaptureSheet> {
  final _controller = TextEditingController();
  final _recorder = AudioRecorder();

  StagedRecording? _staged;
  DateTime? _recordingStarted;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  String? _error;

  static const _sampleRate = 16000;

  @override
  void dispose() {
    _ticker?.cancel();
    // Recording still running means the sheet was dismissed mid-recording:
    // stop and finalize so no audio is ever lost (ТЗ 0.1: durable-сразу).
    final staged = _staged;
    if (staged != null) {
      _finishRecording(staged, popAfter: false);
    }
    _recorder.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await widget.service.createTextNote(text);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleRecording() async {
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
    final newStaged =
        await widget.service.beginAudioNote(extension: 'wav');
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
      await widget.service.abortAudioNote(newStaged);
      if (mounted) setState(() => _error = 'Запись не началась: $e');
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
    _ticker?.cancel();
    _ticker = null;
    final duration = _recordingStarted == null
        ? Duration.zero
        : DateTime.now().difference(_recordingStarted!);
    _staged = null;
    _recordingStarted = null;
    try {
      await _recorder.stop();
      await widget.service.finishAudioNote(
        staged,
        duration: duration,
        codec: 'pcm16-wav',
        sampleRateHz: _sampleRate,
        channels: 1,
      );
    } catch (e) {
      await widget.service.abortAudioNote(staged);
      if (mounted) {
        setState(() => _error = 'Сохранение записи не удалось: $e');
      }
      return;
    }
    if (popAfter && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final recording = _staged != null;
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Быстрая заметка',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Текст или запись аудио…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            recording
                ? 'Запись… ${_elapsed.inMinutes}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}'
                : 'Черновик сохраняется автоматически · проект и теги необязательны',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
              IconButton.filled(
                tooltip: recording ? 'Остановить и сохранить' : 'Записать аудио',
                iconSize: 28,
                onPressed: _toggleRecording,
                icon: Icon(recording ? Icons.stop : Icons.mic),
              ),
              FilledButton(
                onPressed: _saveText,
                child: const Text('Готово'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
