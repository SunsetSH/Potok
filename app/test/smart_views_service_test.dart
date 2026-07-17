import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/note_list_query.dart';
import 'package:potok/application/smart_views_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';

void main() {
  late AppDatabase db;
  late SmartViewsService service;
  late Directory temp;

  const definition = SmartViewDefinition(
    filter: NoteListFilter(
      projectIds: {'p2', 'p1'},
      includeNoProject: true,
      tagIds: {'t2', 't1'},
      tagMatchMode: TagMatchMode.all,
      statuses: {NoteStatus.inWork},
      periodStartUtc: 100,
      periodEndUtcExclusive: 200,
      favoriteOnly: true,
      requireAudio: true,
      requireImage: true,
      requireTranscript: true,
    ),
    order: NoteListOrder(
      field: NoteSortField.updatedAt,
      direction: NoteSortDirection.ascending,
    ),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_smart_views_test');
    service = SmartViewsService(
      db: db,
      clock: FixedClock(DateTime.utc(2026, 7, 17, 10)),
      ids: SequentialIdGenerator(),
      deviceId: 'device-test',
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test('definition round-trips only allowlisted fields deterministically', () {
    final encoded = definition.encode();
    expect(encoded, isNot(contains('SELECT')));
    expect(encoded.indexOf('p1'), lessThan(encoded.indexOf('p2')));

    final decoded = SmartViewDefinition.decode(encoded);
    expect(decoded.filter.projectIds, {'p1', 'p2'});
    expect(decoded.filter.tagIds, {'t1', 't2'});
    expect(decoded.filter.tagMatchMode, TagMatchMode.all);
    expect(decoded.filter.statuses, {NoteStatus.inWork});
    expect(decoded.filter.periodStartUtc, 100);
    expect(decoded.filter.periodEndUtcExclusive, 200);
    expect(decoded.filter.favoriteOnly, isTrue);
    expect(decoded.filter.requireAudio, isTrue);
    expect(decoded.filter.requireImage, isTrue);
    expect(decoded.filter.requireTranscript, isTrue);
    expect(decoded.order.field, NoteSortField.updatedAt);
    expect(decoded.order.direction, NoteSortDirection.ascending);
  });

  test(
    'decoder rejects unknown enums, invalid periods and oversized input',
    () {
      final encoded = definition.encode();
      expect(
        () => SmartViewDefinition.decode(
          encoded.replaceFirst('updatedAt', 'raw SQL column'),
        ),
        throwsFormatException,
      );
      expect(
        () => SmartViewDefinition.decode(
          encoded
              .replaceFirst('"periodStartUtc":100', '"periodStartUtc":300')
              .replaceFirst(
                '"periodEndUtcExclusive":200',
                '"periodEndUtcExclusive":200',
              ),
        ),
        throwsFormatException,
      );
      expect(
        () => SmartViewDefinition.decode('x' * 70000),
        throwsFormatException,
      );
    },
  );

  test('create, guarded update and soft delete are journaled', () async {
    final id = await service.create(
      name: ' Открытые риски ',
      definition: definition,
    );
    var view = (await service.watchViews().first).single;
    expect(view.id, id);
    expect(view.name, 'Открытые риски');
    expect(service.definitionOf(view).filter.tagIds, {'t1', 't2'});

    final stale = view;
    await service.update(view, name: 'Риски', definition: definition);
    view = (await service.watchViews().first).single;
    expect(view.name, 'Риски');
    expect(view.revision, 2);
    await expectLater(
      service.update(stale, name: 'Устарело', definition: definition),
      throwsStateError,
    );

    await service.delete(view);
    expect(await service.watchViews().first, isEmpty);
    final operations = await db.select(db.operationJournal).get();
    expect(
      operations.map((row) => row.operationKind),
      containsAll([
        'smart_view.create',
        'smart_view.update',
        'smart_view.delete',
      ]),
    );
  });
}
