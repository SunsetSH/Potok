import 'package:record/record.dart';

class RecorderLevel {
  final double normalized;
  const RecorderLevel(this.normalized);
}

abstract class AudioRecorderPort {
  Future<bool> hasPermission();
  Future<void> startM4a(String path, {required int bitRate});
  Future<void> pause();
  Future<void> resume();
  Future<String?> stop();
  Future<void> cancel();
  Stream<RecorderLevel> levels();
  Future<void> dispose();
}

class RecordAudioRecorderAdapter implements AudioRecorderPort {
  final AudioRecorder _recorder;

  RecordAudioRecorderAdapter({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> startM4a(String path, {required int bitRate}) {
    return _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: bitRate,
        sampleRate: 44100,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path,
    );
  }

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Stream<RecorderLevel> levels() {
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
  Future<void> dispose() => _recorder.dispose();
}
