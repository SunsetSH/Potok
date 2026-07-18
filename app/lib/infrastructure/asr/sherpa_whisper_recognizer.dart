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
/// (M4A -> mono PCM 16k) lands in WP-03. Model load + decode run in a worker
/// isolate so the UI thread never blocks.
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
    final outcome = await Isolate.run(
      () => _transcribeSync(files, audioPath, languageHint, nativeLibraryDir),
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
    final outcome = await Isolate.run(
      () => _transcribeSamplesSync(
        files,
        samples,
        sampleRate,
        languageHint,
        nativeLibraryDir,
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

  static _SyncOutcome _transcribeSync(
    _ModelFiles files,
    String audioPath,
    String languageHint,
    String? nativeLibraryDir,
  ) {
    _initBindings(nativeLibraryDir);
    final wave = sherpa.readWave(audioPath);
    return _transcribeSamplesSync(
      files,
      Float32List.fromList(wave.samples),
      wave.sampleRate,
      languageHint,
      nativeLibraryDir,
      bindingsInitialized: true,
    );
  }

  static _SyncOutcome _transcribeSamplesSync(
    _ModelFiles files,
    Float32List samples,
    int sampleRate,
    String languageHint,
    String? nativeLibraryDir, {
    bool bindingsInitialized = false,
  }) {
    if (!bindingsInitialized) _initBindings(nativeLibraryDir);
    if (_rms(samples) < 0.002) {
      return _SyncOutcome(
        text: '',
        language: '',
        audioDuration: Duration(
          milliseconds: (samples.length / sampleRate * 1000).round(),
        ),
      );
    }
    final recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: files.encoder,
            decoder: files.decoder,
            language: languageHint,
            task: 'transcribe',
          ),
          tokens: files.tokens,
          modelType: 'whisper',
          numThreads: 2,
          debug: false,
        ),
      ),
    );
    try {
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
        recognizer.decode(stream);
        final result = recognizer.getResult(stream);
        return _SyncOutcome(
          text: result.text.trim(),
          language: result.lang.replaceAll(RegExp(r'[<>|]'), ''),
          audioDuration: Duration(
            milliseconds: (samples.length / sampleRate * 1000).round(),
          ),
        );
      } finally {
        stream.free();
      }
    } finally {
      recognizer.free();
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

  static double _rms(Float32List samples) {
    if (samples.isEmpty) return 0;
    var sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / samples.length);
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

  /// Prefers int8-quantized model files, falls back to fp32.
  static _ModelFiles locate(String dir) {
    final directory = Directory(dir);
    if (!directory.existsSync()) {
      throw ModelUnavailableException('model directory not found: $dir');
    }
    final names = directory
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toSet();

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
