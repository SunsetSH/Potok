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
      expect(
        result.sha256hex,
        '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
      );
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
      expect(() => store.finalize(rel), throwsA(isA<MediaFinalizeException>()));
    });

    test('audio finalize accepts M4A container signature', () async {
      const rel = 'aa/audio.m4a';
      await store.prepareStaging(rel);
      await File(store.stagingPath(rel)).writeAsBytes([
        0,
        0,
        0,
        24,
        0x66,
        0x74,
        0x79,
        0x70,
        0x4d,
        0x34,
        0x41,
        0x20,
      ]);

      final result = await store.finalizeAudio(rel);

      expect(result.sizeBytes, 12);
      expect(File(store.absolutePath(rel)).existsSync(), isTrue);
    });

    test(
      'audio finalize leaves corrupt bytes in staging for recovery',
      () async {
        const rel = 'aa/corrupt.m4a';
        await store.prepareStaging(rel);
        await File(store.stagingPath(rel)).writeAsBytes(List.filled(32, 1));

        await expectLater(
          store.finalizeAudio(rel),
          throwsA(isA<MediaFinalizeException>()),
        );

        expect(File(store.stagingPath(rel)).existsSync(), isTrue);
        expect(File(store.absolutePath(rel)).existsSync(), isFalse);
      },
    );

    test('rejects traversal outside the managed media root', () {
      expect(() => store.absolutePath('../outside.m4a'), throwsArgumentError);
    });

    test('discardStaging is idempotent', () async {
      const rel = '12/1234.wav';
      await store.prepareStaging(rel);
      await File(store.stagingPath(rel)).writeAsBytes([1]);
      await store.discardStaging(rel);
      await store.discardStaging(rel);
      expect(File(store.stagingPath(rel)).existsSync(), isFalse);
    });

    test('discard removes final and partial names idempotently', () async {
      const finalRel = '34/final.png';
      const partialRel = '56/partial.png';
      await store.prepareStaging(finalRel);
      await File(store.absolutePath(finalRel)).writeAsBytes([1]);
      await store.prepareStaging(partialRel);
      await File(store.stagingPath(partialRel)).writeAsBytes([2]);

      await store.discard(finalRel);
      await store.discard(partialRel);
      await store.discard(finalRel);

      expect(File(store.absolutePath(finalRel)).existsSync(), isFalse);
      expect(File(store.stagingPath(partialRel)).existsSync(), isFalse);
    });
  });
}
