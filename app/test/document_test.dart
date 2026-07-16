import 'package:flutter_test/flutter_test.dart';
import 'package:potok/domain/document.dart';

void main() {
  group('PotokDocument', () {
    test('round-trips plain text through the versioned envelope', () {
      final doc = PotokDocument.fromPlainText('первая строка\nвторая');
      final decoded = PotokDocument.decode(doc.encode());
      expect(decoded.plainText, 'первая строка\nвторая');
    });

    test('encodes schema, version and delta format', () {
      final json = PotokDocument.fromPlainText('x').encode();
      expect(json, contains('"schema":"potok.document"'));
      expect(json, contains('"version":1'));
      expect(json, contains('"quill-delta"'));
    });

    test('rejects foreign schema and unsupported version', () {
      expect(
        () => PotokDocument.decode('{"schema":"other","version":1}'),
        throwsFormatException,
      );
      expect(
        () => PotokDocument.decode(
            '{"schema":"potok.document","version":99,"delta":{"ops":[]}}'),
        throwsFormatException,
      );
      expect(() => PotokDocument.decode('[]'), throwsFormatException);
    });

    test('appendParagraph keeps existing content and adds a paragraph', () {
      final doc = PotokDocument.fromPlainText('ручной текст')
          .appendParagraph('расшифровка');
      expect(doc.plainText, 'ручной текст\nрасшифровка');
    });

    test('appendParagraph ignores blank transcript', () {
      final doc = PotokDocument.fromPlainText('a').appendParagraph('   ');
      expect(doc.plainText, 'a');
    });

    test('empty document has empty projection', () {
      expect(const PotokDocument.empty().plainText, '');
      expect(const PotokDocument.empty().isEmpty, isTrue);
    });
  });
}
