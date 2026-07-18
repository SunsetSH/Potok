import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';

enum AudioRecordingFormat { m4a, wavPcm16 }

class AudioInputDevice {
  final String id;
  final String label;
  final String type;

  const AudioInputDevice({
    required this.id,
    required this.label,
    required this.type,
  });
}

class AudioInputDeviceUnavailableException implements Exception {
  final String deviceId;
  const AudioInputDeviceUnavailableException(this.deviceId);
}

enum AudioRecorderStartFailure { permission, device, unsupported, platform }

class AudioRecorderStartException implements Exception {
  final AudioRecorderStartFailure failure;
  const AudioRecorderStartException(this.failure);
}

class RecorderLevel {
  final double normalized;
  const RecorderLevel(this.normalized);
}

abstract class AudioRecorderPort {
  Future<bool> hasPermission();
  Future<List<AudioInputDevice>> listInputDevices();
  Future<void> start(
    String path, {
    required AudioRecordingFormat format,
    required int bitRate,
    String? inputDeviceId,
  });
  Future<void> pause();
  Future<void> resume();
  Future<String?> stop();
  Future<void> cancel();
  Stream<Uint8List> pcm16Chunks();
  Stream<RecorderLevel> levels();
  Future<void> dispose();
}

class RecordAudioRecorderAdapter implements AudioRecorderPort {
  final AudioRecorder _recorder;
  StreamController<Uint8List>? _pcmController;
  StreamController<RecorderLevel>? _pcmLevelController;
  StreamSubscription<Uint8List>? _recordStreamSubscription;
  RandomAccessFile? _wavFile;
  String? _wavPath;
  int _wavDataBytes = 0;
  Future<void> _writeQueue = Future<void>.value();
  Completer<void>? _recordStreamDone;

  RecordAudioRecorderAdapter({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<List<AudioInputDevice>> listInputDevices() async {
    final devices = await _recorder.listInputDevices();
    return devices
        .map(
          (device) => AudioInputDevice(
            id: device.id,
            label: device.label.trim().isEmpty ? 'Микрофон' : device.label,
            type: device.type.name,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> start(
    String path, {
    required AudioRecordingFormat format,
    required int bitRate,
    String? inputDeviceId,
  }) async {
    InputDevice? inputDevice;
    if (inputDeviceId != null && inputDeviceId.isNotEmpty) {
      final devices = await _recorder.listInputDevices();
      for (final device in devices) {
        if (device.id == inputDeviceId) {
          inputDevice = device;
          break;
        }
      }
      if (inputDevice == null) {
        throw AudioInputDeviceUnavailableException(inputDeviceId);
      }
    }
    final config = RecordConfig(
      encoder: format == AudioRecordingFormat.wavPcm16
          ? AudioEncoder.pcm16bits
          : AudioEncoder.aacLc,
      bitRate: bitRate,
      sampleRate: format == AudioRecordingFormat.wavPcm16 ? 16000 : 44100,
      numChannels: 1,
      device: inputDevice,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    );
    try {
      if (format == AudioRecordingFormat.wavPcm16) {
        await _startPcmWav(path, config);
      } else {
        await _recorder.start(config, path: path);
      }
    } on PlatformException catch (error) {
      throw AudioRecorderStartException(_classifyStartFailure(error));
    }
  }

  Future<void> _startPcmWav(String path, RecordConfig config) async {
    final file = await File(path).open(mode: FileMode.write);
    await file.writeFrom(buildPcm16WavHeader(dataBytes: 0));
    final controller = StreamController<Uint8List>.broadcast(sync: true);
    final levelController = StreamController<RecorderLevel>.broadcast(
      sync: true,
    );
    final done = Completer<void>();
    try {
      final stream = await _recorder.startStream(config);
      _wavFile = file;
      _wavPath = path;
      _wavDataBytes = 0;
      _pcmController = controller;
      _pcmLevelController = levelController;
      _recordStreamDone = done;
      _recordStreamSubscription = stream.listen(
        (chunk) {
          if (chunk.isEmpty) return;
          _wavDataBytes += chunk.length;
          _writeQueue = _writeQueue.then((_) => file.writeFrom(chunk));
          controller.add(Uint8List.fromList(chunk));
          levelController.add(RecorderLevel(pcm16RmsLevel(chunk)));
        },
        onError: (Object error, StackTrace stackTrace) {
          controller.addError(error, stackTrace);
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
    } catch (_) {
      await file.close();
      await controller.close();
      await levelController.close();
      rethrow;
    }
  }

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<String?> stop() async {
    final path = _wavPath;
    if (path == null) return _recorder.stop();
    await _recorder.stop();
    final done = _recordStreamDone;
    if (done != null && !done.isCompleted) {
      try {
        await done.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        await _recordStreamSubscription?.cancel();
      }
    }
    await _writeQueue;
    final file = _wavFile;
    if (file != null) {
      await file.setPosition(0);
      await file.writeFrom(buildPcm16WavHeader(dataBytes: _wavDataBytes));
      await file.flush();
      await file.close();
    }
    await _closePcmState();
    return path;
  }

  @override
  Future<void> cancel() async {
    final path = _wavPath;
    await _recorder.cancel();
    await _recordStreamSubscription?.cancel();
    await _writeQueue;
    await _wavFile?.close();
    await _closePcmState();
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
  }

  @override
  Stream<Uint8List> pcm16Chunks() =>
      _pcmController?.stream ?? const Stream<Uint8List>.empty();

  @override
  Stream<RecorderLevel> levels() {
    final pcmLevels = _pcmLevelController;
    if (pcmLevels != null) return pcmLevels.stream;
    return _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).map((
      value,
    ) {
      // record reports dBFS (normally -160..0). Keep UI bounded and do
      // not persist or log microphone samples/levels.
      final normalized = ((value.current + 60) / 60).clamp(0.0, 1.0);
      return RecorderLevel(normalized.toDouble());
    });
  }

  @override
  Future<void> dispose() async {
    await _recordStreamSubscription?.cancel();
    await _wavFile?.close();
    await _closePcmState();
    await _recorder.dispose();
  }

  Future<void> _closePcmState() async {
    final controller = _pcmController;
    final levelController = _pcmLevelController;
    _pcmController = null;
    _pcmLevelController = null;
    _recordStreamSubscription = null;
    _wavFile = null;
    _wavPath = null;
    _wavDataBytes = 0;
    _recordStreamDone = null;
    _writeQueue = Future<void>.value();
    if (controller != null && !controller.isClosed) await controller.close();
    if (levelController != null && !levelController.isClosed) {
      await levelController.close();
    }
  }

  static AudioRecorderStartFailure _classifyStartFailure(
    PlatformException error,
  ) {
    final details = '${error.code} ${error.message} ${error.details}'
        .toLowerCase();
    if (details.contains('access denied') ||
        details.contains('permission') ||
        details.contains('0x80070005')) {
      return AudioRecorderStartFailure.permission;
    }
    if (details.contains('not implemented') ||
        details.contains('unsupported') ||
        details.contains('0x80004001')) {
      return AudioRecorderStartFailure.unsupported;
    }
    if (details.contains('device') ||
        details.contains('not found') ||
        details.contains('0x80070490')) {
      return AudioRecorderStartFailure.device;
    }
    return AudioRecorderStartFailure.platform;
  }
}

/// RMS level for little-endian signed PCM16, normalized from -60 dBFS to 0.
/// It is derived from the exact chunks written to the WAV, so the UI remains
/// responsive even when a platform amplitude callback stalls.
double pcm16RmsLevel(Uint8List bytes) {
  final samples = bytes.length ~/ 2;
  if (samples == 0) return 0;
  final data = ByteData.sublistView(bytes);
  var sumSquares = 0.0;
  for (var index = 0; index < samples; index++) {
    final sample = data.getInt16(index * 2, Endian.little) / 32768.0;
    sumSquares += sample * sample;
  }
  final rms = math.sqrt(sumSquares / samples);
  if (rms <= 0) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 60) / 60).clamp(0.0, 1.0).toDouble();
}

/// RIFF/WAVE envelope used around the PCM stream returned by `record`.
/// Kept public so its byte-level contract can be verified without a device.
Uint8List buildPcm16WavHeader({required int dataBytes}) {
  final bytes = ByteData(44);
  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, 16000, Endian.little);
  bytes.setUint32(28, 16000 * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  return bytes.buffer.asUint8List();
}
