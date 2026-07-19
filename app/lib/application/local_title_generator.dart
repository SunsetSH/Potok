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

    var end = maxLength + 1;
    // Не разрезаем суррогатную пару (например, эмодзи) на границе.
    if (end < normalized.length &&
        (normalized.codeUnitAt(end) & 0xFC00) == 0xDC00) {
      end--;
    }
    var cut = normalized.substring(0, end);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace >= maxLength ~/ 2) cut = cut.substring(0, lastSpace);
    return '${cut.trim()}…';
  }
}
