import 'dart:convert';

/// Canonical rich-document envelope (ADR-003).
///
/// `document_json` is always this versioned envelope; the payload today is a
/// Quill Delta. Plain text is a deterministic projection used for FTS and
/// card previews and is recomputed on every save.
class PotokDocument {
  static const schemaName = 'potok.document';
  static const currentVersion = 1;
  static const deltaFormat = 'quill-delta';

  final List<Map<String, Object?>> ops;

  const PotokDocument._(this.ops);

  const PotokDocument.empty() : ops = const [];

  factory PotokDocument.fromPlainText(String text) {
    if (text.isEmpty) return const PotokDocument.empty();
    // Delta contract: document text always ends with a newline.
    final normalized = text.endsWith('\n') ? text : '$text\n';
    return PotokDocument._([
      {'insert': normalized},
    ]);
  }

  factory PotokDocument.decode(String documentJson) {
    final raw = jsonDecode(documentJson);
    if (raw is! Map<String, Object?>) {
      throw const FormatException('document envelope must be an object');
    }
    if (raw['schema'] != schemaName) {
      throw FormatException('unknown document schema: ${raw['schema']}');
    }
    final version = raw['version'];
    if (version is! int || version < 1 || version > currentVersion) {
      throw FormatException('unsupported document version: $version');
    }
    final delta = raw['delta'];
    final ops = (delta is Map<String, Object?>) ? delta['ops'] : null;
    if (ops is! List) {
      throw const FormatException('document delta.ops missing');
    }
    return PotokDocument._(
      ops.whereType<Map<String, Object?>>().toList(growable: false),
    );
  }

  String encode() => jsonEncode({
        'schema': schemaName,
        'version': currentVersion,
        'format': deltaFormat,
        'delta': {'ops': ops},
      });

  /// Deterministic plain-text projection: concatenated string inserts;
  /// embeds (image/audio) contribute nothing.
  String get plainText {
    final buffer = StringBuffer();
    for (final op in ops) {
      final insert = op['insert'];
      if (insert is String) buffer.write(insert);
    }
    return buffer.toString().trimRight();
  }

  bool get isEmpty => plainText.isEmpty;

  /// Returns a new document with [text] appended as its own paragraph.
  /// Used when a transcript revision is explicitly accepted (FR-ASR-004);
  /// existing user content is never replaced.
  PotokDocument appendParagraph(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return this;
    return PotokDocument._([
      ...ops,
      {'insert': '$trimmed\n'},
    ]);
  }
}
