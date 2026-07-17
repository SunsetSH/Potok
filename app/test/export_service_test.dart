import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/export_service.dart';
import 'package:potok/application/notes_service.dart';
import 'package:potok/domain/clock.dart';
import 'package:potok/domain/document.dart';
import 'package:potok/domain/id_generator.dart';
import 'package:potok/domain/types.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:potok/infrastructure/media_store.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late ExportService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_export_test');
    final notes = NotesService(
      db: db,
      media: MediaStore(temp),
      clock: FixedClock(DateTime.utc(2026, 7, 17, 12)),
      ids: SequentialIdGenerator(),
      deviceId: 'device-test',
    );
    service = ExportService(db: db, notes: notes);
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> seed() async {
    const now = 1752000000000;
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'proj-1',
            name: 'Проект А',
            colorArgb: 0xFF000000,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(
            id: 'tag-1',
            scope: TagScope.global,
            name: 'срочно',
            normalizedName: 'срочно',
            colorArgb: 0xFF112233,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
    // Checklist-документ: две галочки и обычная строка.
    final document = PotokDocument.fromDeltaOps([
      {'insert': 'сделать раз'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
      {'insert': 'сделать два'},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'},
      },
      {'insert': 'обычный текст\n'},
    ]);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'note-1',
            projectId: const Value('proj-1'),
            title: const Value('Список дел'),
            documentJson: document.encode(),
            documentPlainText: document.plainText,
            sourceKind: SourceKind.keyboard,
            createdAtUtc: now,
            updatedAtUtc: now + 1000,
          ),
        );
    await db
        .into(db.noteTags)
        .insert(
          NoteTagsCompanion.insert(
            noteId: 'note-1',
            tagId: 'tag-1',
            assignedAtUtc: now,
          ),
        );
    // Заметка с "опасным" для Excel началом текста.
    final formula = PotokDocument.fromPlainText('=SUM(A1:A2)');
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'note-2',
            documentJson: formula.encode(),
            documentPlainText: formula.plainText,
            sourceKind: SourceKind.keyboard,
            createdAtUtc: now + 2000,
            updatedAtUtc: now + 2000,
          ),
        );
  }

  test('markdown: метаданные и checklist-проекция', () async {
    await seed();
    final notes = await service.collectNotes();
    final markdown = await service.exportMarkdown(notes);

    expect(markdown, contains('## Список дел'));
    expect(markdown, contains('- Проект: Проект А'));
    expect(markdown, contains('- Теги: срочно'));
    expect(markdown, contains('- Статус: В работе'));
    expect(markdown, contains('- Создано: 2025-07-08T18:40:00.000Z'));
    expect(markdown, contains('- [x] сделать раз'));
    expect(markdown, contains('- [ ] сделать два'));
    expect(markdown, contains('обычный текст'));
    // Разделитель между заметками.
    expect(markdown, contains('\n---\n'));
  });

  test('csv: BOM, CRLF и экранирование formula injection', () async {
    await seed();
    final notes = await service.collectNotes();
    final bytes = await service.exportCsv(notes);

    // UTF-8 BOM для Excel.
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    final text = utf8.decode(bytes.sublist(3));
    expect(text, contains('\r\n'));
    expect(
      text.split('\r\n').first,
      'id,project,title,status,tags,created_at,updated_at,plain_text',
    );
    // Значение, начинающееся с '=', экранировано префиксом апострофа.
    expect(text, contains("'=SUM(A1:A2)"));
    expect(text, isNot(contains('\r\n=SUM')));
  });

  test('json: round-trip со stable id', () async {
    await seed();
    final notes = await service.collectNotes();
    final json = await service.exportJson(notes);

    final decoded = jsonDecode(json) as Map<String, Object?>;
    expect(decoded['format'], 'potok.export');
    expect(decoded['version'], 1);
    final items = (decoded['notes'] as List).cast<Map<String, Object?>>();
    expect(items, hasLength(2));
    final first = items.firstWhere((n) => n['id'] == 'note-1');
    expect(first['project_id'], 'proj-1');
    expect(first['title'], 'Список дел');
    final tags = (first['tags'] as List).cast<Map<String, Object?>>();
    expect(tags.single['id'], 'tag-1');
    expect(tags.single['name'], 'срочно');
    // Документ — исходный конверт, пригодный для merge-импорта.
    final document = first['document'] as Map<String, Object?>;
    expect(document['schema'], 'potok.document');
    expect(items.map((n) => n['id']).toSet(), {'note-1', 'note-2'});
  });

  test('collectNotes уважает фильтр раздела (проект)', () async {
    await seed();
    final onlyProject = await service.collectNotes(projectId: 'proj-1');
    expect(onlyProject.map((n) => n.id), ['note-1']);
    final noProject = await service.collectNotes(onlyNoProject: true);
    expect(noProject.map((n) => n.id), ['note-2']);
  });
}
