/// Извлекает голосовые команды классификации («поставь тег…», «в проект…»)
/// из распознанного текста. Полностью локально и детерминированно, без сети.
///
/// Философия устойчивости: парсер намеренно «жадный» — захватывает весь
/// хвост команды до конца предложения, а отсев мусора делает уже сопоставление
/// с РЕАЛЬНО существующими тегами/проектами. Поэтому «Поставь тег важно,
/// купить хлеб» проставит только «важно» (существующий тег), а «купить хлеб»
/// молча отсеется — ничего не создаётся, ложные срабатывания самоограничены.
class VoiceClassifier {
  const VoiceClassifier();

  /// Класс букв (кириллица + латиница); с caseSensitive: false покрывает оба
  /// регистра. `\w` в Dart не включает кириллицу, поэтому диапазон явный.
  static const _l = r'[а-яёa-z]';

  static final String _tagVerb = [
    '(?:по|про)?став$_l*', // поставь / проставь / поставить
    'добав$_l*', // добавь / добавить
    'навес$_l*', // навесь
    'навеша$_l*', // навешай
    'прикреп$_l*', // прикрепи
    'отмет$_l*', // отметь
    'помет$_l*', // пометь
    'помеч$_l*', // помечу
    'размет$_l*', // разметь
    'повес$_l*', // повесь
  ].join('|');

  static final String _projVerb = [
    'занес$_l*', // занеси
    'отправ$_l*', // отправь
    'полож$_l*', // положи
    'помест$_l*', // помести
    'перемест$_l*', // перемести
    'добав$_l*', // добавь
    'постав$_l*', // поставь
  ].join('|');

  /// «(глагол?) тег[и/ом/ами] (:/-/как/это)? <значение до конца предложения>».
  /// Триггер «тег» обязан стоять в начале клаузы или сразу за командным
  /// глаголом — иначе «нужно обсудить теги в отчёте» ложно сработало бы.
  static final RegExp _tagRe = RegExp(
    '(?:^|[.!?;\\n])\\s*'
    '(?:(?:$_tagVerb)\\s+)?'
    'тег$_l*'
    '\\s*[:\\-—]?\\s*'
    '(?:как\\s+|это\\s+)?'
    '([^.!?;\\n]*)',
    caseSensitive: false,
    unicode: true,
  );

  /// Explicit command verbs are safe to recognize even when an ASR model did
  /// not insert punctuation before the command at the end of a note.
  static final RegExp _tagVerbAnywhereRe = RegExp(
    '(?:^|\\s)(?:$_tagVerb)\\s+'
    '(?:тег$_l*|те)'
    '\\s*[:\\-—]?\\s*'
    '(?:как\\s+|это\\s+)?'
    '([^.!?;\\n]*)',
    caseSensitive: false,
    unicode: true,
  );

  /// «отметь/пометь как <значение>» — тег без самого слова «тег».
  static final RegExp _tagAsRe = RegExp(
    '(?:^|[.!?;\\n])\\s*'
    '(?:отмет$_l*|помет$_l*|помеч$_l*)\\s+как\\s+'
    '([^.!?;\\n]*)',
    caseSensitive: false,
    unicode: true,
  );

  /// «(глагол?) (в/во)? проект (:/-)? <значение до конца предложения>».
  static final RegExp _projRe = RegExp(
    '(?:^|[.!?;\\n])\\s*'
    '(?:(?:$_projVerb)\\s+)?'
    '(?:(?:в|во)\\s+)?'
    'проект$_l*'
    '\\s*[:\\-—]?\\s*'
    '([^.!?;\\n]*)',
    caseSensitive: false,
    unicode: true,
  );

  /// The unambiguous `в проект <имя>` form is also accepted mid-utterance;
  /// unlike «в проекте» this describes an action, not ordinary note content.
  static final RegExp _projectInAnywhereRe = RegExp(
    '(?:^|\\s)(?:в|во)\\s+проект\\s*[:\\-—]?\\s*([^.!?;\\n]*)',
    caseSensitive: false,
    unicode: true,
  );

  /// Словесные разделители списка приводятся к запятой перед разбиением —
  /// иначе соседний «,» съедает пробел, нужный «а также»/«и» для совпадения.
  static final RegExp _wordSep = RegExp(
    r'\s+а\s+также\s+|\s+и\s+|\s+плюс\s+',
    unicode: true,
  );

  /// Разбирает [text] на голосовые команды. Ничего не резолвит — только
  /// извлекает произнесённые фразы.
  ParsedVoiceCommands parse(String text) {
    final tagPhrases = <String>[];
    for (final match in _tagRe.allMatches(text)) {
      tagPhrases.addAll(_splitPhrases(match.group(1)));
    }
    for (final match in _tagVerbAnywhereRe.allMatches(text)) {
      tagPhrases.addAll(_splitPhrases(match.group(1)));
    }
    for (final match in _tagAsRe.allMatches(text)) {
      tagPhrases.addAll(_splitPhrases(match.group(1)));
    }

    final projectCandidates = <String>[];
    for (final match in _projRe.allMatches(text)) {
      final phrases = _splitPhrases(match.group(1));
      if (phrases.isEmpty) continue;
      // Имя проекта чаще одно слово сразу после «проект» — пробуем его первым,
      // затем разбитые по разделителям фразы целиком.
      final firstWord = phrases.first.split(' ').first;
      projectCandidates
        ..add(firstWord)
        ..addAll(phrases);
    }
    for (final match in _projectInAnywhereRe.allMatches(text)) {
      final phrases = _splitPhrases(match.group(1));
      if (phrases.isEmpty) continue;
      projectCandidates
        ..add(phrases.first.split(' ').first)
        ..addAll(phrases);
    }

    return ParsedVoiceCommands(
      tagPhrases: _dedupe(tagPhrases),
      projectCandidates: _dedupe(projectCandidates),
    );
  }

  /// Существующие теги, чьё имя совпало с любой из [phrases]. Порядок —
  /// как в [candidates]; дубли исключены.
  List<T> matchTags<T>(
    List<String> phrases,
    List<T> candidates,
    String Function(T) nameOf,
  ) {
    final result = <T>[];
    for (final candidate in candidates) {
      final name = _normalize(nameOf(candidate));
      if (name.isEmpty) continue;
      if (phrases.any((phrase) => _namesMatch(name, phrase))) {
        result.add(candidate);
      }
    }
    return result;
  }

  /// Первый проект, чьё имя совпало с одним из [candidates] (в порядке
  /// произнесения — так одиночное слово-имя проверяется раньше длинных фраз).
  T? matchProject<T>(
    List<String> candidates,
    List<T> projects,
    String Function(T) nameOf,
  ) {
    for (final candidate in candidates) {
      for (final project in projects) {
        if (_namesMatch(_normalize(nameOf(project)), candidate)) {
          return project;
        }
      }
    }
    return null;
  }

  List<String> _splitPhrases(String? span) {
    if (span == null) return const [];
    return span
        .replaceAll(_wordSep, ',')
        .split(RegExp(r'[,;]'))
        .map(_normalize)
        .where((phrase) => phrase.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _dedupe(List<String> items) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in items) {
      if (seen.add(item)) result.add(item);
    }
    return result;
  }

  /// Совпадение имени и произнесённой фразы: точное после нормализации, либо
  /// расстояние Левенштейна ≤ 1 для слов длиной ≥ 5 (терпит одну ошибку ASR,
  /// но не путает короткие теги «риск»/«иск»).
  static bool _namesMatch(String name, String phrase) {
    final variants = <String>[phrase, ...phrase.split(' ')];
    for (final variant in variants) {
      if (name == variant) return true;
      if (name.length >= 5 &&
          variant.length >= 5 &&
          (name.length - variant.length).abs() <= 1 &&
          _levenshtein(name, variant) <= 1) {
        return true;
      }

      // Russian ASR often changes the adjective/noun ending and can attach
      // one stray consonant: «важно» -> «кважная». Within an explicit tag
      // command a shared stem is a safer signal than rejecting the command.
      final stem = _russianStem(name);
      final stemAt = variant.indexOf(stem);
      if (stem.length >= 4 &&
          stemAt >= 0 &&
          stemAt <= 1 &&
          variant.length - stemAt - stem.length <= 3) {
        return true;
      }
    }
    return false;
  }

  static String _russianStem(String value) {
    const endings = <String>[
      'иями',
      'ями',
      'ами',
      'ого',
      'ему',
      'ому',
      'ыми',
      'ими',
      'ая',
      'яя',
      'ый',
      'ий',
      'ой',
      'ое',
      'ее',
      'ую',
      'юю',
      'ие',
      'ые',
      'ам',
      'ям',
      'ах',
      'ях',
      'ом',
      'ем',
      'а',
      'я',
      'о',
      'е',
      'ы',
      'и',
    ];
    for (final ending in endings) {
      if (value.endsWith(ending) && value.length - ending.length >= 4) {
        return value.substring(0, value.length - ending.length);
      }
    }
    return value;
  }

  /// Нормализация: нижний регистр, ё→е (частый разнобой), пунктуация → пробел,
  /// схлопывание пробелов.
  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9 ]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
  }
}

/// Произнесённые фразы команд классификации до сопоставления с сущностями.
class ParsedVoiceCommands {
  /// Фразы после «тег…»/«как…», каждая — кандидат в существующий тег.
  final List<String> tagPhrases;

  /// Кандидаты в проект в порядке произнесения (одиночное слово раньше фраз).
  final List<String> projectCandidates;

  const ParsedVoiceCommands({
    required this.tagPhrases,
    required this.projectCandidates,
  });

  bool get isEmpty => tagPhrases.isEmpty && projectCandidates.isEmpty;
}
