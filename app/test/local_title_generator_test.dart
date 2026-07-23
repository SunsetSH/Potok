import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/local_title_generator.dart';

void main() {
  const generator = LocalTitleGenerator();

  test('uses the first meaningful Russian phrase', () {
    expect(
      generator.suggest('  **Купить билеты**. Затем позвонить в отель.'),
      'Купить билеты',
    );
  });

  test('supports English and truncates on a word boundary', () {
    const short = LocalTitleGenerator(maxLength: 24);
    expect(
      short.suggest('Prepare the release checklist for Windows and Android'),
      'Prepare the release…',
    );
  });

  test('empty content has no suggestion', () {
    expect(generator.suggest('  \n **  '), isNull);
  });

  test('strips a leading filler word from raw ASR text without punctuation', () {
    expect(
      generator.suggest('так короче надо купить билеты в магазине'),
      'надо купить билеты в магазине',
    );
  });

  test('strips a chained filler prefix followed by a comma', () {
    expect(generator.suggest('Ну, короче, надо сделать отчёт.'), 'надо сделать отчёт');
  });

  test('a lone filler word has no suggestion', () {
    expect(generator.suggest('так'), isNull);
  });

  test('does not strip a real word that merely starts with a filler', () {
    // "нужно" начинается не с "ну" как отдельного слова — не должно резаться.
    expect(generator.suggest('нужно купить билеты'), 'нужно купить билеты');
  });

  test('prefers the longer filler phrase over its single-word prefix', () {
    expect(
      generator.suggest('короче говоря надо купить билеты'),
      'надо купить билеты',
    );
    expect(
      generator.suggest('в общем-то надо купить билеты'),
      'надо купить билеты',
    );
  });

  test('peels a chain of several different filler words one by one', () {
    expect(
      generator.suggest('ну вот короче значит надо купить билеты'),
      'надо купить билеты',
    );
  });
}
