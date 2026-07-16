import 'dart:io';
import 'dart:isolate';

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

  SherpaWhisperRecognizer({required this.modelDir});

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
      () => _transcribeSync(files, audioPath, languageHint),
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
  ) {
    sherpa.initBindings();
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
      final wave = sherpa.readWave(audioPath);
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(
          samples: wave.samples,
          sampleRate: wave.sampleRate,
        );
        recognizer.decode(stream);
        final result = recognizer.getResult(stream);
        return _SyncOutcome(
          text: result.text.trim(),
          language: result.lang.replaceAll(RegExp(r'[<>|]'), ''),
          audioDuration: Duration(
            milliseconds:
                (wave.samples.length / wave.sampleRate * 1000).round(),
          ),
        );
      } finally {
        stream.free();
      }
    } finally {
      recognizer.free();
    }
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
      final int8 = names.where((n) => n.endsWith('.int8.onnx') && n.contains(suffix));
      if (int8.isNotEmpty) return p.join(dir, int8.first);
      final fp32 = names.where((n) => n.endsWith('.onnx') && n.contains(suffix));
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
