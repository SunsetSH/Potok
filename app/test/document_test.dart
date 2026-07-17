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
          '{"schema":"potok.document","version":99,"delta":{"ops":[]}}',
        ),
        throwsFormatException,
      );
      expect(() => PotokDocument.decode('[]'), throwsFormatException);
    });

    test('appendParagraph keeps existing content and adds a paragraph', () {
      final doc = PotokDocument.fromPlainText(
        'ручной текст',
      ).appendParagraph('расшифровка');
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

    test('round-trips rich Delta ops and ignores embeds in plain text', () {
      final document = PotokDocument.fromDeltaOps([
        {
          'insert': 'Проверить вход\n',
          'attributes': {'bold': true},
        },
        {
          'insert': {'image': 'asset://image-1'},
          'attributes': {'alt': 'Скриншот ошибки'},
        },
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked'},
        },
      ]);

      final decoded = PotokDocument.decode(document.encode());

      expect(decoded.deltaOps, document.deltaOps);
      expect(decoded.plainText, 'Проверить вход');
    });

    test('takes and returns deep copies of nested Delta data', () {
      final insert = <String, Object?>{'image': 'asset://image-1'};
      final attributes = <String, Object?>{'alt': 'До'};
      final source = <String, Object?>{
        'insert': insert,
        'attributes': attributes,
      };
      final document = PotokDocument.fromDeltaOps([source]);

      insert['image'] = 'asset://changed';
      attributes['alt'] = 'После';
      final exported = document.deltaOps;
      (exported.single['insert'] as Map<String, Object?>)['image'] =
          'asset://also-changed';

      expect(document.deltaOps, [
        {
          'insert': {'image': 'asset://image-1'},
          'attributes': {'alt': 'До'},
        },
      ]);
    });

    test('rejects non-object Delta operations', () {
      expect(
        () => PotokDocument.decode(
          '{"schema":"potok.document","version":1,'
          '"format":"quill-delta","delta":{"ops":["bad"]}}',
        ),
        throwsFormatException,
      );
    });

    test('extracts only valid managed image and audio asset ids', () {
      final document = PotokDocument.fromDeltaOps([
        {
          'insert': {'image': 'asset://IMAGE-1'},
        },
        {
          'insert': {'audio': 'asset://audio-2'},
        },
        {
          'insert': {'image': 'https://example.invalid/tracker.png'},
        },
        {
          'insert': {'image': 'asset://../escape'},
        },
      ]);

      expect(document.managedAssetIds, {'IMAGE-1', 'audio-2'});
    });
  });
}
