import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Model files needed to build a sherpa-onnx offline recognizer. Covers both
/// architectures the app supports: encoder-decoder (Whisper) and transducer
/// (NeMo-style — GigaAM, Parakeet TDT). [joiner] stays empty for Whisper.
class SherpaModelFiles {
  final String modelType;
  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;

  const SherpaModelFiles({
    required this.modelType,
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
  });
}

/// One decode request for the shared worker isolate. Either [audioPath]
/// (final WAV) or [samples] (preview chunk) is set.
class SherpaAsrRequest {
  final SherpaModelFiles files;
  final String? audioPath;
  final Float32List? samples;
  final int sampleRate;
  final String languageHint;
  final String? nativeLibraryDir;
  final bool applySilenceGate;

  const SherpaAsrRequest({
    required this.files,
    required this.audioPath,
    required this.samples,
    required this.sampleRate,
    required this.languageHint,
    required this.nativeLibraryDir,
    required this.applySilenceGate,
  });

  /// Cache identity of the native recognizer this request needs.
  String get recognizerKey =>
      '${files.modelType}|${files.encoder}|${files.decoder}|'
      '${files.joiner}|${files.tokens}|$languageHint';
}

class SherpaAsrOutcome {
  final String text;
  final String language;
  final Duration audioDuration;

  const SherpaAsrOutcome({
    required this.text,
    required this.language,
    required this.audioDuration,
  });
}

double sherpaRms(Float32List samples) {
  if (samples.isEmpty) return 0;
  var sumSquares = 0.0;
  for (final sample in samples) {
    sumSquares += sample * sample;
  }
  return math.sqrt(sumSquares / samples.length);
}

/// Removes only long silence at the edges while retaining padding around
/// speech. NeMo/Parakeet transducers can return an empty hypothesis when a
/// short phrase follows tens of seconds of leading silence. Short pauses and
/// silence inside speech are deliberately untouched.
Float32List trimLongEdgeSilence(
  Float32List samples,
  int sampleRate, {
  double threshold = 0.002,
  Duration minimumSilence = const Duration(seconds: 2),
  Duration padding = const Duration(milliseconds: 400),
}) {
  if (samples.isEmpty || sampleRate <= 0) return samples;
  final frameSize = math.max(1, sampleRate ~/ 20); // 50 ms
  var firstSignal = -1;
  var lastSignal = -1;
  for (var start = 0; start < samples.length; start += frameSize) {
    final end = math.min(start + frameSize, samples.length);
    var sumSquares = 0.0;
    for (var index = start; index < end; index++) {
      sumSquares += samples[index] * samples[index];
    }
    final rms = math.sqrt(sumSquares / (end - start));
    if (rms >= threshold) {
      firstSignal = firstSignal < 0 ? start : firstSignal;
      lastSignal = end;
    }
  }
  if (firstSignal < 0) return samples;
  final minimumSamples = minimumSilence.inMilliseconds * sampleRate ~/ 1000;
  final paddingSamples = padding.inMilliseconds * sampleRate ~/ 1000;
  final trimStart = firstSignal >= minimumSamples
      ? math.max(0, firstSignal - paddingSamples)
      : 0;
  final trailingSilence = samples.length - lastSignal;
  final trimEnd = trailingSilence >= minimumSamples
      ? math.min(samples.length, lastSignal + paddingSamples)
      : samples.length;
  if (trimStart == 0 && trimEnd == samples.length) return samples;
  return Float32List.sublistView(samples, trimStart, trimEnd);
}

/// Long-lived ASR isolate shared by every sherpa-onnx recognizer
/// architecture. Requests are processed sequentially (the port is a natural
/// queue), which also serializes CPU-heavy decodes and keeps at most one
/// native recognizer resident at a time — switching between an installed
/// Whisper pack and a transducer pack (GigaAM/Parakeet) frees the previous
/// one before loading the next.
class SherpaAsrWorker {
  static final SherpaAsrWorker instance = SherpaAsrWorker._();

  SherpaAsrWorker._();

  Future<SendPort>? _starting;
  Isolate? _isolate;

  Future<SendPort> _ensureStarted() {
    return _starting ??= () async {
      final ready = ReceivePort();
      final isolate = await Isolate.spawn(
        _entry,
        ready.sendPort,
        debugName: 'potok-asr-worker',
      );
      final commands = await ready.first as SendPort;
      ready.close();
      _isolate = isolate;
      return commands;
    }();
  }

  Future<SherpaAsrOutcome> run(SherpaAsrRequest request) async {
    final commands = await _ensureStarted();
    final reply = ReceivePort();
    commands.send([reply.sendPort, request]);
    final response = await reply.first;
    reply.close();
    if (response is SherpaAsrOutcome) return response;
    final envelope = response as List<Object?>;
    final error = envelope[0];
    final stackTrace = StackTrace.fromString(envelope[1] as String? ?? '');
    if (error is Object) Error.throwWithStackTrace(error, stackTrace);
    throw StateError('ASR worker returned no result');
  }

  Future<void> dispose() async {
    final starting = _starting;
    if (starting == null) return;
    _starting = null;
    final isolate = _isolate;
    _isolate = null;
    final commands = await starting;
    final done = ReceivePort();
    commands.send([done.sendPort, null]);
    await done.first; // native recognizer freed inside the isolate
    done.close();
    isolate?.kill(priority: Isolate.immediate);
  }

  static void _entry(SendPort ready) {
    final commands = ReceivePort();
    ready.send(commands.sendPort);
    sherpa.OfflineRecognizer? recognizer;
    String? recognizerKey;
    var bindingsReady = false;
    commands.listen((Object? message) {
      final envelope = message as List<Object?>;
      final reply = envelope[0] as SendPort;
      final request = envelope[1];
      if (request == null) {
        // Shutdown: release the cached native recognizer before the kill.
        recognizer?.free();
        recognizer = null;
        recognizerKey = null;
        commands.close();
        reply.send(true);
        return;
      }
      try {
        final asrRequest = request as SherpaAsrRequest;
        if (!bindingsReady) {
          _initBindings(asrRequest.nativeLibraryDir);
          bindingsReady = true;
        }
        final key = asrRequest.recognizerKey;
        if (recognizer == null || recognizerKey != key) {
          recognizer?.free();
          recognizer = null;
          recognizerKey = null;
          recognizer = _createRecognizer(asrRequest);
          recognizerKey = key;
        }
        reply.send(_decode(recognizer!, asrRequest));
      } catch (error, stackTrace) {
        try {
          reply.send([error, stackTrace.toString()]);
        } catch (_) {
          // The error itself is not sendable across isolates.
          reply.send([StateError(error.toString()), stackTrace.toString()]);
        }
      }
    });
  }

  static sherpa.OfflineRecognizer _createRecognizer(SherpaAsrRequest request) {
    final files = request.files;
    final sherpa.OfflineModelConfig model;
    if (files.modelType == 'whisper') {
      model = sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: files.encoder,
          decoder: files.decoder,
          language: request.languageHint,
          task: 'transcribe',
        ),
        tokens: files.tokens,
        modelType: 'whisper',
        numThreads: 2,
        debug: false,
      );
    } else {
      // NeMo-style transducer (GigaAM, Parakeet TDT): encoder/decoder/joiner
      // triple instead of Whisper's encoder-decoder pair.
      model = sherpa.OfflineModelConfig(
        transducer: sherpa.OfflineTransducerModelConfig(
          encoder: files.encoder,
          decoder: files.decoder,
          joiner: files.joiner,
        ),
        tokens: files.tokens,
        modelType: 'nemo_transducer',
        numThreads: 2,
        debug: false,
      );
    }
    return sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(model: model),
    );
  }

  static SherpaAsrOutcome _decode(
    sherpa.OfflineRecognizer recognizer,
    SherpaAsrRequest request,
  ) {
    final Float32List samples;
    final int sampleRate;
    final audioPath = request.audioPath;
    if (audioPath != null) {
      _validateWavFile(audioPath);
      final wave = sherpa.readWave(audioPath);
      if (wave.sampleRate <= 0) {
        throw FormatException('WAV с некорректным sample rate', audioPath);
      }
      samples = Float32List.fromList(wave.samples);
      sampleRate = wave.sampleRate;
    } else {
      samples = request.samples!;
      sampleRate = request.sampleRate;
      if (sampleRate <= 0) {
        throw const FormatException('некорректный sample rate');
      }
    }
    final audioDuration = Duration(
      milliseconds: (samples.length / sampleRate * 1000).round(),
    );
    if (request.applySilenceGate && sherpaRms(samples) < 0.002) {
      return SherpaAsrOutcome(
        text: '',
        language: '',
        audioDuration: audioDuration,
      );
    }
    final decodeSamples =
        request.files.modelType == 'nemo_transducer' && audioPath != null
        ? trimLongEdgeSilence(samples, sampleRate)
        : samples;
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: decodeSamples, sampleRate: sampleRate);
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      return SherpaAsrOutcome(
        text: result.text.trim(),
        language: result.lang.replaceAll(RegExp(r'[<>|]'), ''),
        audioDuration: audioDuration,
      );
    } finally {
      stream.free();
    }
  }

  /// Cheap sanity checks before handing the path to native code: a missing or
  /// non-RIFF file must fail as a normal queue error, not NaN/native crash.
  static void _validateWavFile(String audioPath) {
    final file = File(audioPath);
    if (!file.existsSync()) {
      throw FormatException('аудиофайл не найден', audioPath);
    }
    final handle = file.openSync();
    try {
      final header = handle.readSync(12);
      final riffWave =
          header.length >= 12 &&
          header[0] == 0x52 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x46 &&
          header[8] == 0x57 &&
          header[9] == 0x41 &&
          header[10] == 0x56 &&
          header[11] == 0x45;
      if (!riffWave) {
        throw FormatException('файл не является WAV', audioPath);
      }
    } finally {
      handle.closeSync();
    }
  }

  static void _initBindings(String? nativeLibraryDir) {
    if (Platform.isWindows && nativeLibraryDir != null) {
      // Force the matching ORT beside the sherpa DLL into this isolate. This
      // matters for host tools that may have another onnxruntime.dll on their
      // search path; packaged applications already place both DLLs together.
      DynamicLibrary.open(p.join(nativeLibraryDir, 'onnxruntime.dll'));
    }
    sherpa.initBindings(nativeLibraryDir);
  }
}
