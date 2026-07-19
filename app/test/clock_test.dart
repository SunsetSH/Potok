import 'package:flutter_test/flutter_test.dart';
import 'package:potok/domain/clock.dart';

void main() {
  group('FixedClock', () {
    test('nowUtc returns the given time normalized to UTC', () {
      final clock = FixedClock(DateTime.utc(2026, 1, 1, 12));
      expect(clock.nowUtc().isUtc, isTrue);
      expect(clock.nowUtc(), DateTime.utc(2026, 1, 1, 12));
    });

    test('nowUtc normalizes a local DateTime to UTC', () {
      final local = DateTime(2026, 1, 1, 12);
      final clock = FixedClock(local);
      expect(clock.nowUtc().isUtc, isTrue);
      expect(clock.nowUtc(), local.toUtc());
    });

    test('nowUtcMillis matches nowUtc milliseconds', () {
      final clock = FixedClock(DateTime.utc(2026, 1, 1));
      expect(clock.nowUtcMillis(), clock.nowUtc().millisecondsSinceEpoch);
    });

    test('advance moves the clock forward by the given duration', () {
      final clock = FixedClock(DateTime.utc(2026, 1, 1, 0, 0, 0));
      clock.advance(const Duration(hours: 2));
      expect(clock.nowUtc(), DateTime.utc(2026, 1, 1, 2, 0, 0));
      clock.advance(const Duration(minutes: 30));
      expect(clock.nowUtc(), DateTime.utc(2026, 1, 1, 2, 30, 0));
    });
  });

  group('SystemClock', () {
    const clock = SystemClock();

    test('nowUtc returns a UTC time close to the real current time', () {
      final before = DateTime.now().toUtc();
      final now = clock.nowUtc();
      final after = DateTime.now().toUtc();

      expect(now.isUtc, isTrue);
      expect(now.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(now.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('nowUtcMillis is consistent with nowUtc', () {
      final millis = clock.nowUtcMillis();
      final now = clock.nowUtc().millisecondsSinceEpoch;
      expect((now - millis).abs() < 1000, isTrue);
    });
  });
}
