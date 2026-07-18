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
}
