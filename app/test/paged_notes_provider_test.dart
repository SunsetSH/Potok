import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/document.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';
import 'package:potok/presentation/providers.dart';

void main() {
  test('paged provider loads the journal incrementally', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final temp = await Directory.systemTemp.createTemp('potok_paged_provider');
    addTearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });
    final service = NotesService(
      db: db,
      media: MediaStore(temp),
      clock: FixedClock(DateTime.utc(2026, 7, 17)),
      ids: SequentialIdGenerator(),
      deviceId: 'device-test',
    );
    final document = PotokDocument.fromPlainText('row').encode();
    await db.batch(
      (batch) => batch.insertAll(
        db.notes,
        List.generate(
          120,
          (index) => NotesCompanion.insert(
            id: 'note-${index.toString().padLeft(3, '0')}',
            documentJson: document,
            documentPlainText: 'row $index',
            sourceKind: SourceKind.keyboard,
            createdAtUtc: index,
            updatedAtUtc: index,
          ),
          growable: false,
        ),
      ),
    );

    final container = ProviderContainer(
      overrides: [notesServiceProvider.overrideWith((ref) => service)],
    );
    addTearDown(container.dispose);

    final first = await container.read(pagedSectionNotesProvider.future);
    expect(first.notes, hasLength(50));
    expect(first.notes.first.id, 'note-119');
    expect(first.hasMore, isTrue);

    await container.read(pagedSectionNotesProvider.notifier).loadMore();
    var state = container.read(pagedSectionNotesProvider).requireValue;
    expect(state.notes, hasLength(100));
    expect(state.notes.toSet(), hasLength(100));
    expect(state.hasMore, isTrue);

    await container.read(pagedSectionNotesProvider.notifier).loadMore();
    state = container.read(pagedSectionNotesProvider).requireValue;
    expect(state.notes, hasLength(120));
    expect(state.notes.last.id, 'note-000');
    expect(state.hasMore, isFalse);
  });
}
