import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'local_speech_recognizer.dart';

/// sherpa-onnx offline Whisper adapter (ADR-002).
///
/// Slice limitation: accepts WAV input only; the compressed-source decode step
/// (M4A -> mono PCM 16k) lands in WP-03. Decoding runs in one long-lived
/// worker isolate that caches the native [sherpa.OfflineRecognizer], so the UI
/// thread never blocks and the ONNX model is not reloaded per file/preview
/// chunk. The cache is invalidated when the model files or language change;
/// [disposeWorker] frees the native recognizer and the isolate.
class SherpaWhisperRecognizer implements LocalSpeechRecognizer {
  final String modelDir;
  final String? nativeLibraryDir;

  SherpaWhisperRecognizer({required this.modelDir, this.nativeLibraryDir});

  @override
  String get engineId => 'sherpa-onnx';

  String get modelId => p.basename(modelDir);

  @override
  Future<TranscriptionResult> transcribeFile(
    String audioPath, {
    String languageHint = '',
  }) async {
    final files = _ModelFiles.locate(modelDir);
    final started = DateTime.now();
    final outcome = await _AsrWorker.instance.run(
      _AsrRequest(
        files: files,
        audioPath: audioPath,
        samples: null,
        sampleRate: 0,
        languageHint: languageHint,
        nativeLibraryDir: nativeLibraryDir,
        // Финальная расшифровка не глушится silence-gate: тихая речь всё
        // равно уходит в декодер, пустой текст возможен только от модели.
        applySilenceGate: false,
      ),
    );
    return TranscriptionResult(
      text: outcome.text,
      modelId: modelId,
      language: outcome.language,
      audioDuration: outcome.audioDuration,
      processingTime: DateTime.now().difference(started),
    );
  }

  /// Decodes one completed PCM chunk for the capture preview. The final
  /// durable transcription still uses [transcribeFile] over the whole WAV.
  Future<TranscriptionResult> transcribeSamples(
    Float32List samples, {
    int sampleRate = 16000,
    String languageHint = '',
  }) async {
    final files = _ModelFiles.locate(modelDir);
    final started = DateTime.now();
    final outcome = await _AsrWorker.instance.run(
      _AsrRequest(
        files: files,
        audioPath: null,
        samples: samples,
        sampleRate: sampleRate,
        languageHint: languageHint,
        nativeLibraryDir: nativeLibraryDir,
        applySilenceGate: true,
      ),
    );
    return TranscriptionResult(
      text: outcome.text,
      modelId: modelId,
      language: outcome.language,
      audioDuration: outcome.audioDuration,
      processingTime: DateTime.now().difference(started),
    );
  }

  /// Frees the shared worker isolate and its cached native recognizer.
  /// The next transcription transparently restarts the worker.
  static Future<void> disposeWorker() => _AsrWorker.instance.dispose();

  /// Instance-level alias: recognizer instances are cheap facades over the
  /// shared worker, so disposing any of them releases the shared resources.
  Future<void> dispose() => disposeWorker();

  static double _rms(Float32List samples) {
    if (samples.isEmpty) return 0;
    var sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / samples.length);
  }
}

/// One decode request for the worker isolate. Either [audioPath] (final WAV)
/// or [samples] (preview chunk) is set.
class _AsrRequest {
  final _ModelFiles files;
  final String? audioPath;
  final Float32List? samples;
  final int sampleRate;
  final String languageHint;
  final String? nativeLibraryDir;
  final bool applySilenceGate;

  const _AsrRequest({
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
      '${files.encoder}|${files.decoder}|${files.tokens}|$languageHint';
}

/// Long-lived ASR isolate. Requests are processed sequentially (the port is a
/// natural queue), which also serializes CPU-heavy decodes.
class _AsrWorker {
  static final _AsrWorker instance = _AsrWorker._();

  _AsrWorker._();

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

  Future<_SyncOutcome> run(_AsrRequest request) async {
    final commands = await _ensureStarted();
    final reply = ReceivePort();
    commands.send([reply.sendPort, request]);
    final response = await reply.first;
    reply.close();
    if (response is _SyncOutcome) return response;
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
        final asrRequest = request as _AsrRequest;
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

  static sherpa.OfflineRecognizer _createRecognizer(_AsrRequest request) {
    return sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: request.files.encoder,
            decoder: request.files.decoder,
            language: request.languageHint,
            task: 'transcribe',
          ),
          tokens: request.files.tokens,
          modelType: 'whisper',
          numThreads: 2,
          debug: false,
        ),
      ),
    );
  }

  static _SyncOutcome _decode(
    sherpa.OfflineRecognizer recognizer,
    _AsrRequest request,
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
    if (request.applySilenceGate &&
        SherpaWhisperRecognizer._rms(samples) < 0.002) {
      return _SyncOutcome(text: '', language: '', audioDuration: audioDuration);
    }
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      return _SyncOutcome(
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

class _ModelFiles {
  final String encoder;
  final String decoder;
  final String tokens;

  const _ModelFiles({
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  /// Prefers int8-quantized model files, falls back to fp32. Candidate names
  /// are sorted so the selection is deterministic across platforms.
  static _ModelFiles locate(String dir) {
    final directory = Directory(dir);
    if (!directory.existsSync()) {
      throw ModelUnavailableException('model directory not found: $dir');
    }
    final names =
        directory
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .toList()
          ..sort();

    String pick(String suffix) {
      final int8 = names.where(
        (n) => n.endsWith('.int8.onnx') && n.contains(suffix),
      );
      if (int8.isNotEmpty) return p.join(dir, int8.first);
      final fp32 = names.where(
        (n) => n.endsWith('.onnx') && n.contains(suffix),
      );
      if (fp32.isNotEmpty) return p.join(dir, fp32.first);
      throw ModelUnavailableException('missing $suffix model in $dir');
    }

    final tokens = names.where((n) => n.endsWith('tokens.txt'));
    if (tokens.isEmpty) {
      throw ModelUnavailableException('missing tokens.txt in $dir');
    }
    return _ModelFiles(
      encoder: pick('encoder'),
      decoder: pick('decoder'),
      tokens: p.join(dir, tokens.first),
    );
  }
}

class _SyncOutcome {
  final String text;
  final String language;
  final Duration audioDuration;

  const _SyncOutcome({
    required this.text,
    required this.language,
    required this.audioDuration,
  });
}
