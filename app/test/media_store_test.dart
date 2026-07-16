import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:potok/infrastructure/media_store.dart';

void main() {
  late Directory temp;
  late MediaStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('potok_media_test');
    store = MediaStore(temp);
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  group('MediaStore finalize protocol', () {
    test('promotes staged file atomically and returns size + sha256', () async {
      const rel = 'ab/abc123.wav';
      await store.prepareStaging(rel);
      await File(store.stagingPath(rel)).writeAsBytes([1, 2, 3, 4]);

      final result = await store.finalize(rel);

      expect(result.sizeBytes, 4);
      expect(result.sha256hex,
          '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a');
      expect(File(store.absolutePath(rel)).existsSync(), isTrue);
      expect(File(store.stagingPath(rel)).existsSync(), isFalse);
    });

    test('rejects missing staged file', () async {
      expect(
        () => store.finalize('cd/cdef.wav'),
        throwsA(isA<MediaFinalizeException>()),
      );
    });

    test('rejects empty staged file (crash before flush)', () async {
      const rel = 'ef/ef01.wav';
      await store.prepareStaging(rel);
      await File(store.stagingPath(rel)).create();
      expect(
        () => store.finalize(rel),
        throwsA(isA<MediaFinalizeException>()),
      );
    });

    test('discardStaging is idempotent', () async {
      const rel = '12/1234.wav';
      await store.prepareStaging(rel);
      await File(store.stagingPath(rel)).writeAsBytes([1]);
      await store.discardStaging(rel);
      await store.discardStaging(rel);
      expect(File(store.stagingPath(rel)).existsSync(), isFalse);
    });
  });
}
