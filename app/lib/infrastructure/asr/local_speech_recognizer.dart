import 'dart:typed_data';

/// Adapter contract for local ASR engines (ТЗ 0.8.2, ADR-002).
/// Implementations must work fully offline and never own a network client.
abstract interface class LocalSpeechRecognizer {
  String get engineId;

  /// Transcribes an audio file into text. [languageHint] is a BCP-47 primary
  /// tag ('ru', 'en') or empty for auto/multilingual.
  Future<TranscriptionResult> transcribeFile(
    String audioPath, {
    String languageHint = '',
  });

  /// Decodes one completed PCM16 chunk for the capture live preview. The
  /// final durable transcription still goes through [transcribeFile] over
  /// the whole recording.
  Future<TranscriptionResult> transcribeSamples(
    Float32List samples, {
    int sampleRate = 16000,
    String languageHint = '',
  });
}

class TranscriptionResult {
  final String text;
  final String modelId;
  final String language;
  final Duration audioDuration;
  final Duration processingTime;

  const TranscriptionResult({
    required this.text,
    required this.modelId,
    required this.language,
    required this.audioDuration,
    required this.processingTime,
  });
}

/// Expected failure: engine present but no usable model pack installed.
class ModelUnavailableException implements Exception {
  final String message;
  const ModelUnavailableException(this.message);

  @override
  String toString() => 'ModelUnavailableException: $message';
}
