import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/voice_classifier.dart';

void main() {
  const classifier = VoiceClassifier();

  String nameOf(String s) => s;

  group('tag parsing', () {
    test('"Теги: вопрос, задача" extracts both phrases', () {
      final parsed = classifier.parse('Теги: вопрос, задача');
      expect(parsed.tagPhrases, ['вопрос', 'задача']);
    });

    test('leading verb "поставь тег важно"', () {
      final parsed = classifier.parse('Поставь тег важно');
      expect(parsed.tagPhrases, ['важно']);
    });

    test('"добавь теги вопрос и риск" — connector "и"', () {
      final parsed = classifier.parse('добавь теги вопрос и риск');
      expect(parsed.tagPhrases, ['вопрос', 'риск']);
    });

    test('"тегами вопрос, а также задача"', () {
      final parsed = classifier.parse('тегами вопрос, а также задача');
      expect(parsed.tagPhrases, ['вопрос', 'задача']);
    });

    test('"отметь как срочно" without the word "тег"', () {
      final parsed = classifier.parse('Отметь как срочно');
      expect(parsed.tagPhrases, ['срочно']);
    });

    test('tag command after a sentence, note text preserved separately', () {
      final parsed = classifier.parse('Купить билеты. Тег: важно');
      expect(parsed.tagPhrases, ['важно']);
    });

    test('explicit tag command works after unpunctuated ASR text', () {
      final parsed = classifier.parse(
        'Купить билеты на завтра поставь тег важно',
      );
      expect(parsed.tagPhrases, contains('важно'));
    });

    test('tolerates common live-ASR noise in an explicit tag command', () {
      final parsed = classifier.parse('Поставь те кважная');
      expect(parsed.tagPhrases, contains('кважная'));
      expect(classifier.matchTags(parsed.tagPhrases, ['Важно'], nameOf), [
        'Важно',
      ]);
    });

    test('"теги" mid-sentence is NOT a command', () {
      final parsed = classifier.parse('Нужно обсудить теги в отчёте');
      expect(parsed.tagPhrases, isEmpty);
    });
  });

  group('project parsing', () {
    test('"в проект Работа"', () {
      final parsed = classifier.parse('В проект Работа');
      expect(parsed.projectCandidates, contains('работа'));
    });

    test('"проект: Дом"', () {
      final parsed = classifier.parse('Проект: Дом');
      expect(parsed.projectCandidates, contains('дом'));
    });

    test('"в проект" works after unpunctuated ASR text', () {
      final parsed = classifier.parse(
        'Купить билеты на завтра в проект Работа',
      );
      expect(parsed.projectCandidates, contains('работа'));
    });

    test(
      '"занеси в проект Работа купить билеты" — first word is candidate',
      () {
        final parsed = classifier.parse('Занеси в проект Работа купить билеты');
        // Первое слово "работа" — кандидат, поэтому проект резолвится даже без
        // запятой после названия.
        expect(parsed.projectCandidates.first, 'работа');
      },
    );

    test('"в проекте всё готово" is not a usable command', () {
      final parsed = classifier.parse('В проекте всё готово');
      // Захват есть, но ни один кандидат не совпадёт с реальным проектом.
      final match = classifier.matchProject(parsed.projectCandidates, [
        'Работа',
        'Дом',
      ], nameOf);
      expect(match, isNull);
    });
  });

  group('resolution against existing entities', () {
    test('only existing tags are matched, garbage dropped', () {
      final parsed = classifier.parse('Поставь тег важно, купить хлеб');
      final matched = classifier.matchTags(parsed.tagPhrases, [
        'Важно',
        'Вопрос',
        'Задача',
      ], nameOf);
      expect(matched, ['Важно']);
    });

    test('case-insensitive and ё/е-insensitive matching', () {
      final parsed = classifier.parse('тег СРОЧНО');
      final matched = classifier.matchTags(parsed.tagPhrases, [
        'срочно',
      ], nameOf);
      expect(matched, ['срочно']);
    });

    test('tolerates a single ASR typo in a long name', () {
      final parsed = classifier.parse(
        'тег требвание',
      ); // "требование" с опечаткой
      final matched = classifier.matchTags(parsed.tagPhrases, [
        'Требование',
      ], nameOf);
      expect(matched, ['Требование']);
    });

    test('does not fuzzy-match short distinct tags', () {
      final parsed = classifier.parse('тег иск');
      final matched = classifier.matchTags(parsed.tagPhrases, ['Риск'], nameOf);
      expect(matched, isEmpty);
    });

    test('project resolves against existing project by name', () {
      final parsed = classifier.parse('В проект Дом');
      final project = classifier.matchProject(parsed.projectCandidates, [
        'Работа',
        'Дом',
      ], nameOf);
      expect(project, 'Дом');
    });
  });

  group('combined and empty', () {
    test('tags and project in one utterance', () {
      final parsed = classifier.parse(
        'Купить билеты. Теги: вопрос, важно. В проект Работа',
      );
      expect(
        classifier.matchTags(parsed.tagPhrases, [
          'Вопрос',
          'Важно',
          'Риск',
        ], nameOf),
        ['Вопрос', 'Важно'],
      );
      expect(
        classifier.matchProject(parsed.projectCandidates, ['Работа'], nameOf),
        'Работа',
      );
    });

    test('plain note without commands yields nothing', () {
      final parsed = classifier.parse(
        'Завтра встреча с командой в десять утра',
      );
      expect(parsed.isEmpty, isTrue);
    });
  });
}
