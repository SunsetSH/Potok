import 'package:uuid/uuid.dart';

/// ID source abstraction (ТЗ 0.8.2: IIdGenerator).
abstract interface class IdGenerator {
  String newId();
}

/// UUIDv7: time-ordered, safe as a stable tie-breaker in sorts (ADR-004).
class UuidV7Generator implements IdGenerator {
  static const _uuid = Uuid();

  const UuidV7Generator();

  @override
  String newId() => _uuid.v7();
}

/// Deterministic generator for tests: id-1, id-2, ...
class SequentialIdGenerator implements IdGenerator {
  final String prefix;
  int _counter = 0;

  SequentialIdGenerator({this.prefix = 'id'});

  @override
  String newId() => '$prefix-${(++_counter).toString().padLeft(4, '0')}';
}
