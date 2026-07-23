import 'dart:io';

import '../infrastructure/widget_recording_inbox.dart';
import 'notes_service.dart';

typedef WidgetRecordingPublished =
    Future<void> Function(String noteId, String assetId);

class WidgetRecordingImportReport {
  final int imported;
  final int failed;

  const WidgetRecordingImportReport({
    required this.imported,
    required this.failed,
  });
}

/// Publishes native widget recordings through the canonical audio-note use case.
class WidgetRecordingImportService {
  final NotesService notes;
  final WidgetRecordingInbox inbox;
  final WidgetRecordingPublished? onPublished;

  const WidgetRecordingImportService({
    required this.notes,
    required this.inbox,
    this.onPublished,
  });

  Future<WidgetRecordingImportReport> importPending() async {
    var imported = 0;
    var failed = 0;
    for (final entry in await inbox.pending()) {
      StagedRecording? staged;
      try {
        staged = await notes.beginOrResumeWidgetAudioNote(entry.id);
        if (staged != null) {
          await _copyDurably(entry.audioFile, File(staged.stagingPath));
          await notes.finishAudioNote(
            staged,
            duration: entry.duration,
            codec: 'pcm16-wav',
            sampleRateHz: entry.sampleRateHz,
            channels: entry.channels,
          );
          try {
            await onPublished?.call(staged.noteId, staged.assetId);
          } catch (_) {
            // The audio commit is authoritative; ASR can be retried manually.
          }
        }
        await inbox.acknowledge(entry);
        imported += 1;
      } catch (_) {
        failed += 1;
        if (staged != null) {
          try {
            await notes.abortAudioNote(staged);
          } catch (_) {
            // Preserve the inbox pair so the next startup can retry safely.
          }
        }
      }
    }
    return WidgetRecordingImportReport(imported: imported, failed: failed);
  }

  Future<void> _copyDurably(File source, File target) async {
    await target.parent.create(recursive: true);
    final input = await source.open();
    final output = await target.open(mode: FileMode.write);
    try {
      await output.truncate(0);
      const chunkSize = 64 * 1024;
      while (true) {
        final chunk = await input.read(chunkSize);
        if (chunk.isEmpty) break;
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await input.close();
      await output.close();
    }
  }
}
