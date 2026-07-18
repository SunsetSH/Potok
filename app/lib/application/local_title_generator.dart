/// Fast, deterministic and fully local note-title suggestion.
///
/// This is deliberately extractive, not marketed as AI: it selects the first
/// meaningful phrase and never sends content outside the process.
class LocalTitleGenerator {
  final int maxLength;

  const LocalTitleGenerator({this.maxLength = 72});

  String? suggest(String content) {
    var normalized = content
        .replaceAll(RegExp(r'[`*_>#\[\]{}]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return null;

    final boundary = normalized.indexOf(RegExp(r'[.!?;:\n]'));
    if (boundary >= 12) normalized = normalized.substring(0, boundary);
    normalized = normalized.trim().replaceAll(RegExp(r'^[\-–—,:;\s]+'), '');
    if (normalized.isEmpty) return null;
    if (normalized.length <= maxLength) return normalized;

    var cut = normalized.substring(0, maxLength + 1);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace >= maxLength ~/ 2) cut = cut.substring(0, lastSpace);
    return '${cut.trim()}…';
  }
}
