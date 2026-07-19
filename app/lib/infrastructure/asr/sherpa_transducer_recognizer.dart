import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'local_speech_recognizer.dart';
import 'sherpa_asr_worker.dart';

/// sherpa-onnx offline NeMo-transducer adapter: covers GigaAM (Russian) and
/// NVIDIA Parakeet TDT (multilingual) model packs, which both export to the
/// same encoder/decoder/joiner + tokens.txt layout via sherpa-onnx's NeMo
/// transducer conversion scripts. Shares the isolate-caching worker with
/// [SherpaWhisperRecognizer] — only the native model config differs.
class SherpaTransducerRecognizer implements LocalSpeechRecognizer {
  final String modelDir;
  final String? nativeLibraryDir;

  SherpaTransducerRecognizer({required this.modelDir, this.nativeLibraryDir});

  @override
  String get engineId => 'sherpa-onnx';

  String get modelId => p.basename(modelDir);

  @override
  Future<TranscriptionResult> transcribeFile(
    String audioPath, {
    String languageHint = '',
  }) async {
    final files = _locateTransducerFiles(modelDir);
    final started = DateTime.now();
    final outcome = await SherpaAsrWorker.instance.run(
      SherpaAsrRequest(
        files: files,
        audioPath: audioPath,
        samples: null,
        sampleRate: 0,
        languageHint: languageHint,
        nativeLibraryDir: nativeLibraryDir,
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

  @override
  Future<TranscriptionResult> transcribeSamples(
    Float32List samples, {
    int sampleRate = 16000,
    String languageHint = '',
  }) async {
    final files = _locateTransducerFiles(modelDir);
    final started = DateTime.now();
    final outcome = await SherpaAsrWorker.instance.run(
      SherpaAsrRequest(
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
  static Future<void> disposeWorker() => SherpaAsrWorker.instance.dispose();

  Future<void> dispose() => disposeWorker();
}

/// Prefers int8-quantized model files, falls back to fp32. Candidate names
/// are sorted so the selection is deterministic across platforms.
SherpaModelFiles _locateTransducerFiles(String dir) {
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
    final fp32 = names.where((n) => n.endsWith('.onnx') && n.contains(suffix));
    if (fp32.isNotEmpty) return p.join(dir, fp32.first);
    throw ModelUnavailableException('missing $suffix model in $dir');
  }

  final tokens = names.where((n) => n.endsWith('tokens.txt'));
  if (tokens.isEmpty) {
    throw ModelUnavailableException('missing tokens.txt in $dir');
  }
  return SherpaModelFiles(
    modelType: 'nemo_transducer',
    encoder: pick('encoder'),
    decoder: pick('decoder'),
    joiner: pick('joiner'),
    tokens: p.join(dir, tokens.first),
  );
}
