import 'package:flutter_test/flutter_test.dart';
import 'package:potok/domain/id_generator.dart';

final _uuidV7Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  group('UuidV7Generator', () {
    const generator = UuidV7Generator();

    test('generates ids matching the UUIDv7 format', () {
      final id = generator.newId();
      expect(id, matches(_uuidV7Pattern));
    });

    test('generates unique ids under bulk generation', () {
      final ids = List.generate(10000, (_) => generator.newId());
      expect(ids.toSet().length, ids.length);
    });

    test('generates time-ordered (monotonic) ids', () {
      // UUIDv7 stores the 48-bit millisecond timestamp in the leading 12
      // hex digits, so generation order must be non-decreasing there.
      final ids = List.generate(1000, (_) => generator.newId());
      final timestamps = ids
          .map((id) => id.replaceAll('-', '').substring(0, 12))
          .toList();
      for (var i = 1; i < timestamps.length; i++) {
        expect(
          timestamps[i].compareTo(timestamps[i - 1]),
          greaterThanOrEqualTo(0),
          reason: 'id ${ids[i]} is older than ${ids[i - 1]}',
        );
      }
    });
  });

  group('SequentialIdGenerator', () {
    test('uses the default prefix and increments the counter', () {
      final generator = SequentialIdGenerator();
      expect(generator.newId(), 'id-0001');
      expect(generator.newId(), 'id-0002');
      expect(generator.newId(), 'id-0003');
    });

    test('uses a custom prefix', () {
      final generator = SequentialIdGenerator(prefix: 'note');
      expect(generator.newId(), 'note-0001');
      expect(generator.newId(), 'note-0002');
    });

    test('counters of separate instances are independent', () {
      final a = SequentialIdGenerator(prefix: 'a');
      final b = SequentialIdGenerator(prefix: 'b');
      a.newId();
      a.newId();
      expect(a.newId(), 'a-0003');
      expect(b.newId(), 'b-0001');
    });
  });
}
