/// Domain enums and invariants (ТЗ 0.5, 0.7). Stored as snake_case strings.
enum NoteStatus {
  inWork('in_work'),
  done('done');

  final String db;
  const NoteStatus(this.db);
}

enum SourceKind { keyboard, audio, import_, share, widget }

enum AssetKind { image, audio }

/// Media finalize protocol states (ADR-004).
enum AssetLifecycle { staging, ready, missing, deleted }

/// Local ASR job/transcript states (ТЗ 0.3.1).
enum TranscriptState {
  queued,
  recognizing,
  ready,
  failed,
  cancelled,
  waitingForModel,
}
