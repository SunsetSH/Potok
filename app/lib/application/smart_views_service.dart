import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/clock.dart';
import '../domain/id_generator.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import 'note_list_query.dart';

class SmartViewDefinition {
  static const currentVersion = 1;
  static const maxEncodedBytes = 64 * 1024;

  final NoteListFilter filter;
  final NoteListOrder order;

  const SmartViewDefinition({required this.filter, required this.order});

  String encode() {
    final projects = filter.projectIds.toList()..sort();
    final tags = filter.tagIds.toList()..sort();
    final statuses = filter.statuses.map((status) => status.db).toList()
      ..sort();
    final encoded = jsonEncode({
      'version': currentVersion,
      'filter': {
        'projectIds': projects,
        'includeNoProject': filter.includeNoProject,
        'tagIds': tags,
        'tagMatchMode': filter.tagMatchMode.name,
        'statuses': statuses,
        'periodStartUtc': filter.periodStartUtc,
        'periodEndUtcExclusive': filter.periodEndUtcExclusive,
        'favoriteOnly': filter.favoriteOnly,
        'requireAudio': filter.requireAudio,
        'requireImage': filter.requireImage,
        'requireTranscript': filter.requireTranscript,
      },
      'order': {'field': order.field.name, 'direction': order.direction.name},
    });
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw const FormatException('smart view definition is too large');
    }
    return encoded;
  }

  static SmartViewDefinition decode(String raw) {
    if (utf8.encode(raw).length > maxEncodedBytes) {
      throw const FormatException('smart view definition is too large');
    }
    final root = jsonDecode(raw);
    if (root is! Map<String, Object?> ||
        root['version'] != currentVersion ||
        root['filter'] is! Map<String, Object?> ||
        root['order'] is! Map<String, Object?>) {
      throw const FormatException('unsupported smart view definition');
    }
    final filterJson = root['filter']! as Map<String, Object?>;
    final orderJson = root['order']! as Map<String, Object?>;
    final projectIds = _stringSet(filterJson['projectIds'], maxItems: 100);
    final tagIds = _stringSet(filterJson['tagIds'], maxItems: 20);
    final statuses = _stringList(filterJson['statuses'], maxItems: 2)
        .map(
          (value) => NoteStatus.values.firstWhere(
            (status) => status.db == value,
            orElse: () => throw const FormatException('unknown note status'),
          ),
        )
        .toSet();
    final start = _nullableInt(filterJson['periodStartUtc']);
    final end = _nullableInt(filterJson['periodEndUtcExclusive']);
    if (start != null && end != null && start >= end) {
      throw const FormatException('invalid smart view period');
    }
    return SmartViewDefinition(
      filter: NoteListFilter(
        projectIds: projectIds,
        includeNoProject: _bool(filterJson, 'includeNoProject'),
        tagIds: tagIds,
        tagMatchMode: _enumByName(
          TagMatchMode.values,
          filterJson['tagMatchMode'],
        ),
        statuses: statuses,
        periodStartUtc: start,
        periodEndUtcExclusive: end,
        favoriteOnly: _bool(filterJson, 'favoriteOnly'),
        requireAudio: _bool(filterJson, 'requireAudio'),
        requireImage: _bool(filterJson, 'requireImage'),
        requireTranscript: _bool(filterJson, 'requireTranscript'),
      ),
      order: NoteListOrder(
        field: _enumByName(NoteSortField.values, orderJson['field']),
        direction: _enumByName(
          NoteSortDirection.values,
          orderJson['direction'],
        ),
      ),
    );
  }

  static Set<String> _stringSet(Object? value, {required int maxItems}) =>
      _stringList(value, maxItems: maxItems).toSet();

  static List<String> _stringList(Object? value, {required int maxItems}) {
    if (value is! List<Object?> || value.length > maxItems) {
      throw const FormatException('invalid smart view string list');
    }
    final result = <String>[];
    for (final item in value) {
      if (item is! String || item.isEmpty || item.length > 200) {
        throw const FormatException('invalid smart view string');
      }
      result.add(item);
    }
    return result;
  }

  static bool _bool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! bool) throw FormatException('invalid smart view $key');
    return value;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    if (value is! int || value < 0) {
      throw const FormatException('invalid smart view timestamp');
    }
    return value;
  }

  static T _enumByName<T extends Enum>(List<T> values, Object? value) {
    if (value is! String) {
      throw const FormatException('invalid smart view enum');
    }
    return values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw const FormatException('unknown smart view enum'),
    );
  }
}

class SmartViewsService {
  final AppDatabase db;
  final Clock clock;
  final IdGenerator ids;
  final String deviceId;

  SmartViewsService({
    required this.db,
    required this.clock,
    required this.ids,
    required this.deviceId,
  });

  Stream<List<SmartView>> watchViews() {
    final query = db.select(db.smartViews)
      ..where((view) => view.deletedAtUtc.isNull())
      ..orderBy([
        (view) => OrderingTerm.asc(view.sortOrder),
        (view) => OrderingTerm.asc(view.name.collate(Collate.noCase)),
        (view) => OrderingTerm.asc(view.id),
      ]);
    return query.watch();
  }

  Future<String> create({
    required String name,
    required SmartViewDefinition definition,
  }) async {
    final trimmed = _validateName(name);
    final encoded = definition.encode();
    final id = ids.newId();
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      await db
          .into(db.smartViews)
          .insert(
            SmartViewsCompanion.insert(
              id: id,
              name: trimmed,
              definitionVersion: SmartViewDefinition.currentVersion,
              definitionJson: encoded,
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      await _journal(id, 'smart_view.create', null, 1, now);
    });
    return id;
  }

  Future<void> update(
    SmartView view, {
    required String name,
    required SmartViewDefinition definition,
  }) async {
    final trimmed = _validateName(name);
    final encoded = definition.encode();
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final changed =
          await (db.update(db.smartViews)..where(
                (row) =>
                    row.id.equals(view.id) & row.revision.equals(view.revision),
              ))
              .write(
                SmartViewsCompanion(
                  name: Value(trimmed),
                  definitionVersion: const Value(
                    SmartViewDefinition.currentVersion,
                  ),
                  definitionJson: Value(encoded),
                  updatedAtUtc: Value(now),
                  revision: Value(view.revision + 1),
                ),
              );
      if (changed == 0) {
        throw StateError('smart view was modified concurrently');
      }
      await _journal(
        view.id,
        'smart_view.update',
        view.revision,
        view.revision + 1,
        now,
      );
    });
  }

  Future<void> delete(SmartView view) async {
    final now = clock.nowUtcMillis();
    await db.transaction(() async {
      final changed =
          await (db.update(db.smartViews)..where(
                (row) =>
                    row.id.equals(view.id) & row.revision.equals(view.revision),
              ))
              .write(
                SmartViewsCompanion(
                  deletedAtUtc: Value(now),
                  updatedAtUtc: Value(now),
                  revision: Value(view.revision + 1),
                ),
              );
      if (changed == 0) {
        throw StateError('smart view was modified concurrently');
      }
      await _journal(
        view.id,
        'smart_view.delete',
        view.revision,
        view.revision + 1,
        now,
      );
    });
  }

  SmartViewDefinition definitionOf(SmartView view) {
    if (view.definitionVersion != SmartViewDefinition.currentVersion) {
      throw const FormatException('unsupported smart view row version');
    }
    return SmartViewDefinition.decode(view.definitionJson);
  }

  static String _validateName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.length > 120) {
      throw ArgumentError('smart view name must be 1..120 chars');
    }
    return name;
  }

  Future<void> _journal(
    String entityId,
    String operation,
    int? baseRevision,
    int newRevision,
    int at,
  ) => db
      .into(db.operationJournal)
      .insert(
        OperationJournalCompanion.insert(
          operationId: ids.newId(),
          deviceId: deviceId,
          entityKind: 'smart_view',
          entityId: entityId,
          baseRevision: Value(baseRevision),
          newRevision: Value(newRevision),
          operationKind: operation,
          occurredAtUtc: at,
        ),
      );
}
