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

    test('rejects mismatched delta format', () {
      expect(
        () => PotokDocument.decode(
          '{"schema":"potok.document","version":1,'
          '"format":"other-format","delta":{"ops":[]}}',
        ),
        throwsFormatException,
      );
    });

    test('accepts missing format field for backward compatibility', () {
      final decoded = PotokDocument.decode(
        '{"schema":"potok.document","version":1,"delta":{"ops":[]}}',
      );
      expect(decoded.plainText, '');
    });

    test('distinguishes an unsupported newer version from corrupt data', () {
      expect(
        () => PotokDocument.decode(
          '{"schema":"potok.document","version":99,"delta":{"ops":[]}}',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('newer'),
          ),
        ),
      );
      expect(
        () => PotokDocument.decode(
          '{"schema":"potok.document","version":0,"delta":{"ops":[]}}',
        ),
        throwsFormatException,
      );
    });

    test('rejects a document missing the delta entirely', () {
      expect(
        () => PotokDocument.decode(
          '{"schema":"potok.document","version":1,"format":"quill-delta"}',
        ),
        throwsFormatException,
      );
    });

    test('rejects syntactically invalid JSON', () {
      expect(
        () => PotokDocument.decode('{not valid json'),
        throwsFormatException,
      );
    });

    test('appendImage rejects an invalid assetId', () {
      final document = PotokDocument.fromPlainText('текст');
      expect(
        () => document.appendImage('bad/id'),
        throwsArgumentError,
      );
      expect(
        () => document.appendImage(''),
        throwsArgumentError,
      );
    });

    test('deep-copies nested ops three levels deep', () {
      final nested = <String, Object?>{
        'level2': <String, Object?>{
          'level3': <String, Object?>{'value': 'исходное'},
        },
      };
      final source = <String, Object?>{'insert': 'x', 'level1': nested};
      final document = PotokDocument.fromDeltaOps([source]);

      (((nested['level2'] as Map<String, Object?>)['level3']
              as Map<String, Object?>))['value'] =
          'изменено';

      final exported = document.deltaOps.single;
      final level1 = exported['level1'] as Map<String, Object?>;
      final level2 = level1['level2'] as Map<String, Object?>;
      final level3 = level2['level3'] as Map<String, Object?>;
      expect(level3['value'], 'исходное');
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

    test(
      'appendImage creates a managed embed without plain-text pollution',
      () {
        final document = PotokDocument.fromPlainText(
          'Подпись',
        ).appendImage('image-42', alt: 'Скриншот');

        expect(document.plainText, 'Подпись');
        expect(document.managedAssetIds, {'image-42'});
        final imageOp = document.deltaOps.firstWhere(
          (op) => op['insert'] is Map<String, Object?>,
        );
        expect(imageOp['attributes'], {'alt': 'Скриншот', 'display': 'wide'});
      },
    );
  });
}
