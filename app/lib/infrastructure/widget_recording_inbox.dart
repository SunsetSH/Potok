import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class WidgetRecordingInboxEntry {
  final String id;
  final File audioFile;
  final File metadataFile;
  final Duration duration;
  final int sampleRateHz;
  final int channels;

  const WidgetRecordingInboxEntry({
    required this.id,
    required this.audioFile,
    required this.metadataFile,
    required this.duration,
    required this.sampleRateHz,
    required this.channels,
  });
}

/// Validates the bounded hand-off written by the Android microphone service.
/// It never follows links or accepts paths supplied outside the inbox root.
class WidgetRecordingInbox {
  static const maxEntries = 32;
  static const maxMetadataBytes = 4096;
  static const maxAudioBytes = 60 * 1024 * 1024;
  static final _safeId = RegExp(r'^[A-Za-z0-9-]{1,64}$');

  final Directory root;

  const WidgetRecordingInbox(this.root);

  Future<List<WidgetRecordingInboxEntry>> pending() async {
    if (!root.existsSync()) return const [];
    final metadata = await root
        .list(followLinks: false)
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .take(maxEntries)
        .toList();
    metadata.sort(
      (left, right) =>
          left.lastModifiedSync().compareTo(right.lastModifiedSync()),
    );

    final result = <WidgetRecordingInboxEntry>[];
    for (final file in metadata) {
      final parsed = await _parse(file);
      if (parsed == null) {
        await _quarantine(file);
      } else {
        result.add(parsed);
      }
    }
    return result;
  }

  Future<void> acknowledge(WidgetRecordingInboxEntry entry) async {
    if (entry.audioFile.existsSync()) entry.audioFile.deleteSync();
    if (entry.metadataFile.existsSync()) entry.metadataFile.deleteSync();
  }

  Future<WidgetRecordingInboxEntry?> _parse(File metadataFile) async {
    try {
      final size = await metadataFile.length();
      if (size <= 0 || size > maxMetadataBytes) return null;
      final decoded = jsonDecode(await metadataFile.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
        return null;
      }
      final id = decoded['id'];
      final fileName = decoded['file'];
      final durationMs = decoded['durationMs'];
      final sampleRateHz = decoded['sampleRateHz'];
      final channels = decoded['channels'];
      if (id is! String || !_safeId.hasMatch(id) || fileName != '$id.wav') {
        return null;
      }
      if (durationMs is! int ||
          durationMs <= 0 ||
          durationMs > 30 * 60 * 1000) {
        return null;
      }
      if (sampleRateHz != 16000 || channels != 1) return null;

      final rootPath = p.normalize(p.absolute(root.path));
      final audioPath = p.normalize(p.join(rootPath, fileName as String));
      if (!p.isWithin(rootPath, audioPath)) return null;
      final audioFile = File(audioPath);
      if (!audioFile.existsSync()) return null;
      final audioSize = await audioFile.length();
      if (audioSize <= 44 || audioSize > maxAudioBytes) return null;
      final signature = await audioFile
          .openRead(0, 12)
          .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
      if (signature.length != 12 ||
          ascii.decode(signature.sublist(0, 4)) != 'RIFF' ||
          ascii.decode(signature.sublist(8, 12)) != 'WAVE') {
        return null;
      }
      return WidgetRecordingInboxEntry(
        id: id,
        audioFile: audioFile,
        metadataFile: metadataFile,
        duration: Duration(milliseconds: durationMs),
        sampleRateHz: sampleRateHz as int,
        channels: channels as int,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _quarantine(File metadata) async {
    try {
      final target = File('${metadata.path}.invalid');
      if (target.existsSync()) target.deleteSync();
      await metadata.rename(target.path);
    } catch (_) {
      // Leave the untrusted file untouched if even quarantine is unavailable.
    }
  }
}

class WidgetRecordingEventPort {
  static const channelName = 'dev.potok/widget_recordings';
  final MethodChannel channel;

  WidgetRecordingEventPort({this.channel = const MethodChannel(channelName)});

  void listen(Future<void> Function()? onAvailable) {
    if (onAvailable == null) {
      channel.setMethodCallHandler(null);
      return;
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'recordingAvailable') await onAvailable();
    });
  }
}
