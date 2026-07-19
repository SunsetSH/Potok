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

  /// Строит документ из Quill Delta ops (`Document.toDelta().toJson()`).
  /// Ops копируются: последующие правки редактора не меняют снимок.
  factory PotokDocument.fromDeltaOps(List<Map<String, Object?>> ops) {
    return PotokDocument._(ops.map(_copyJsonObject).toList(growable: false));
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
    if (version is! int || version < 1) {
      throw FormatException('unsupported document version: $version');
    }
    if (version > currentVersion) {
      throw FormatException('unsupported newer document version: $version');
    }
    final format = raw['format'];
    if (format != null && format != deltaFormat) {
      throw FormatException('unsupported document delta format: $format');
    }
    final delta = raw['delta'];
    final ops = (delta is Map<String, Object?>) ? delta['ops'] : null;
    if (ops is! List) {
      throw const FormatException('document delta.ops missing');
    }
    if (ops.any((op) => op is! Map<String, Object?>)) {
      throw const FormatException('document delta.ops must contain objects');
    }
    return PotokDocument._(
      ops
          .cast<Map<String, Object?>>()
          .map(_copyJsonObject)
          .toList(growable: false),
    );
  }

  String encode() => jsonEncode({
    'schema': schemaName,
    'version': currentVersion,
    'format': deltaFormat,
    'delta': {'ops': ops},
  });

  /// Ops в формате, который принимает Quill `Document.fromJson`.
  /// Копия: правки Quill-документа не мутируют снимок.
  List<Map<String, Object?>> get deltaOps =>
      ops.map(_copyJsonObject).toList(growable: false);

  /// Deterministic plain-text projection (FTS, card preview): concatenated
  /// string inserts. Checklist-строки — обычный текст (атрибуты строки живут
  /// на '\n' и на проекцию не влияют); embeds (image/audio) contribute
  /// nothing.
  String get plainText {
    final buffer = StringBuffer();
    for (final op in ops) {
      final insert = op['insert'];
      if (insert is String) buffer.write(insert);
    }
    return buffer.toString().trimRight();
  }

  bool get isEmpty => plainText.isEmpty;

  /// Managed media referenced by image/audio embeds. Unknown schemes and
  /// malformed values are ignored; callers never interpret them as paths.
  Set<String> get managedAssetIds {
    final result = <String>{};
    for (final op in ops) {
      final insert = op['insert'];
      if (insert is! Map<String, Object?>) continue;
      for (final kind in const ['image', 'audio']) {
        final value = insert[kind];
        if (value is! String || !value.startsWith('asset://')) continue;
        final id = value.substring('asset://'.length);
        if (id.isNotEmpty && !id.contains(RegExp(r'[/\\?#]'))) {
          result.add(id);
        }
      }
    }
    return Set.unmodifiable(result);
  }

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

  PotokDocument appendImage(String assetId, {String alt = 'Изображение'}) {
    if (assetId.isEmpty || assetId.contains(RegExp(r'[/\\?#]'))) {
      throw ArgumentError.value(assetId, 'assetId', 'invalid managed asset id');
    }
    return PotokDocument._([
      ...ops,
      {
        'insert': {'image': 'asset://$assetId'},
        'attributes': {
          'alt': alt.trim().isEmpty ? 'Изображение' : alt.trim(),
          'display': 'wide',
        },
      },
      {'insert': '\n'},
    ]);
  }
}

Map<String, Object?> _copyJsonObject(Map<String, Object?> source) =>
    source.map((key, value) => MapEntry(key, _copyJsonValue(value)));

Object? _copyJsonValue(Object? value) => switch (value) {
  final Map<String, Object?> map => _copyJsonObject(map),
  final List<Object?> list => list.map(_copyJsonValue).toList(growable: false),
  _ => value,
};
