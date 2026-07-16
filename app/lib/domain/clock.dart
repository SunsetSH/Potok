/// Time source abstraction (ТЗ 0.8.2: IClock). Production code never calls
/// DateTime.now() directly — this keeps time-dependent invariants testable.
abstract interface class Clock {
  DateTime nowUtc();

  int nowUtcMillis();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  int nowUtcMillis() => nowUtc().millisecondsSinceEpoch;
}

/// Deterministic clock for tests; advances only when told to.
class FixedClock implements Clock {
  DateTime current;

  FixedClock(DateTime start) : current = start.toUtc();

  @override
  DateTime nowUtc() => current;

  @override
  int nowUtcMillis() => current.millisecondsSinceEpoch;

  void advance(Duration by) => current = current.add(by);
}
