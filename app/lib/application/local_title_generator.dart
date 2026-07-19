/// Fast, deterministic and fully local note-title suggestion.
///
/// This is deliberately extractive, not marketed as AI: it selects the first
/// meaningful phrase and never sends content outside the process.
class LocalTitleGenerator {
  final int maxLength;

  const LocalTitleGenerator({this.maxLength = 72});

  /// Слова-паразиты в начале голосовых заметок ("так, короче, надо
  /// сказать..."). Если первое предложение целиком состоит из них, оно не
  /// годится в заголовок — берём то, что идёт дальше.
  static const _leadingFillers = [
    'так',
    'короче',
    'значит',
    'ну',
    'типа',
    'вообще',
    'кстати',
    'ладно',
    'итак',
    'стало быть',
  ];

  String? suggest(String content) {
    final normalized = content
        .replaceAll(RegExp(r'[`*_>#\[\]{}]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return null;

    var chosen = '';
    for (final candidate in _splitSentences(normalized)) {
      final stripped = _stripLeadingFillers(candidate);
      if (stripped.isNotEmpty) {
        chosen = stripped;
        break;
      }
    }
    if (chosen.isEmpty) return null;
    chosen = chosen.replaceAll(RegExp(r'^[\-–—,:;\s]+'), '').trim();
    if (chosen.isEmpty) return null;
    if (chosen.length <= maxLength) return chosen;

    var end = maxLength + 1;
    // Не разрезаем суррогатную пару (например, эмодзи) на границе.
    if (end < chosen.length &&
        (chosen.codeUnitAt(end) & 0xFC00) == 0xDC00) {
      end--;
    }
    var cut = chosen.substring(0, end);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace >= maxLength ~/ 2) cut = cut.substring(0, lastSpace);
    return '${cut.trim()}…';
  }

  /// Первое предложение (до `.!?;:\n`) и остаток текста как запасной
  /// кандидат — если первое целиком оказалось словами-паразитами. Короткий
  /// префикс до знака препинания (аббревиатура вроде "т.е.") не считается
  /// границей предложения — как и в исходной версии эвристики.
  static List<String> _splitSentences(String normalized) {
    final boundary = normalized.indexOf(RegExp(r'[.!?;:\n]'));
    if (boundary < 12) return [normalized];
    final rest = normalized.substring(boundary + 1).trim();
    final first = normalized.substring(0, boundary).trim();
    return rest.isEmpty ? [first] : [first, rest];
  }

  static String _stripLeadingFillers(String sentence) {
    var s = sentence.trim();
    var changed = true;
    while (changed) {
      changed = false;
      final lower = s.toLowerCase();
      for (final filler in _leadingFillers) {
        if (lower == filler) {
          s = '';
          break;
        }
        if (lower.length > filler.length &&
            lower.startsWith(filler) &&
            !_isWordChar(lower.codeUnitAt(filler.length))) {
          s = s
              .substring(filler.length)
              .replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '');
          changed = s.isNotEmpty;
          break;
        }
      }
    }
    return s.trim();
  }

  static bool _isWordChar(int codeUnit) =>
      RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(
        String.fromCharCode(codeUnit),
      );
}
