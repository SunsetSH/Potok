import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/document.dart';
import '../infrastructure/db/database.dart';
import 'note_list_query.dart';
import 'notes_service.dart';

enum ExportFormat {
  markdown('Markdown', 'md'),
  csv('CSV', 'csv'),
  json('JSON', 'json');

  final String label;
  final String extension;
  const ExportFormat(this.label, this.extension);
}

/// Экспорт заметок в Markdown/CSV/JSON (FR-EXP-001..004, ADR-006).
/// Аудио и изображения в текстовые форматы не встраиваются — только пометки.
class ExportService {
  /// Верхняя граница выборки: экспорт — не sync-механизм.
  static const maxNotes = 10000;

  final AppDatabase db;
  final NotesService notes;

  ExportService({required this.db, required this.notes});

  /// Заметки текущего раздела/выборки в порядке отображения.
  Future<List<Note>> collectNotes({
    String? projectId,
    bool onlyNoProject = false,
    bool onlyFavorites = false,
    NoteListFilter filter = const NoteListFilter(),
    NoteListOrder order = const NoteListOrder(),
  }) async {
    final result = <Note>[];
    NoteListCursor? cursor;
    while (result.length < maxNotes) {
      final page = await notes.fetchNotesPage(
        projectId: projectId,
        onlyNoProject: onlyNoProject,
        onlyFavorites: onlyFavorites,
        filter: filter,
        order: order,
        after: cursor,
        pageSize: 200,
      );
      result.addAll(page.notes);
      if (!page.hasMore || page.nextCursor == null) break;
      cursor = page.nextCursor;
    }
    // Последняя страница может перешагнуть лимит — усекаем, иначе
    // _loadContext честно откажет всему экспорту.
    if (result.length > maxNotes) result.length = maxNotes;
    return result;
  }

  // ---------- Markdown (FR-EXP-003) ----------

  Future<String> exportMarkdown(List<Note> selection) async {
    final context = await _loadContext(selection);
    final buffer = StringBuffer();
    var first = true;
    for (final note in selection) {
      if (!first) buffer.write('\n---\n\n');
      first = false;
      final title = _titleOf(note);
      buffer.writeln('## ${title.isEmpty ? 'Без названия' : title}');
      buffer.writeln();
      final project = context.projectNames[note.projectId];
      buffer.writeln('- Проект: ${project ?? '—'}');
      final tags = context.tagsByNote[note.id] ?? const <String>[];
      buffer.writeln('- Теги: ${tags.isEmpty ? '—' : tags.join(', ')}');
      buffer.writeln('- Статус: ${_statusLabel(note)}');
      buffer.writeln('- Создано: ${_formatUtc(note.createdAtUtc)}');
      buffer.writeln('- Изменено: ${_formatUtc(note.updatedAtUtc)}');
      buffer.writeln();
      final body = _renderBody(note);
      if (body.isNotEmpty) buffer.writeln(body);
      for (final durationMs in context.audioByNote[note.id] ?? const <int>[]) {
        buffer.writeln('[аудио: ${(durationMs / 1000).round()} сек]');
      }
    }
    return buffer.toString();
  }

  // ---------- CSV (FR-EXP-004) ----------

  /// UTF-8 c BOM и CRLF — так CSV корректно открывается в Excel.
  Future<List<int>> exportCsv(List<Note> selection) async {
    final context = await _loadContext(selection);
    final rows = <List<String>>[
      const [
        'id',
        'project',
        'title',
        'status',
        'tags',
        'created_at',
        'updated_at',
        'plain_text',
      ],
      for (final note in selection)
        [
          note.id,
          context.projectNames[note.projectId] ?? '',
          _titleOf(note),
          note.status.db,
          (context.tagsByNote[note.id] ?? const <String>[]).join('; '),
          _formatUtc(note.createdAtUtc),
          _formatUtc(note.updatedAtUtc),
          note.documentPlainText,
        ],
    ];
    final csv = rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
    return utf8.encode('﻿$csv\r\n');
  }

  /// Formula injection: значения, начинающиеся с `=`, `+`, `-`, `@`,
  /// экранируются префиксом `'` (FR-EXP-004).
  static String _csvCell(String raw) {
    var value = raw;
    if (value.isNotEmpty && '=+-@'.contains(value[0])) {
      value = "'$value";
    }
    if (value.contains(RegExp(r'[",\r\n]'))) {
      value = '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  // ---------- JSON (машиночитаемый, stable ID для FR-IMP-003) ----------

  Future<String> exportJson(List<Note> selection) async {
    final context = await _loadContext(selection);
    final payload = <String, Object?>{
      'format': 'potok.export',
      'version': 1,
      'exported_at_utc': DateTime.now().toUtc().toIso8601String(),
      'notes': [
        for (final note in selection)
          {
            'id': note.id,
            'project_id': note.projectId,
            'title': note.title,
            'status': note.status.db,
            'tags': [
              for (final tag in context.tagRowsByNote[note.id] ?? const <Tag>[])
                {'id': tag.id, 'name': tag.name},
            ],
            'document': jsonDecode(note.documentJson),
            'created_at_utc': _formatUtc(note.createdAtUtc),
            'updated_at_utc': _formatUtc(note.updatedAtUtc),
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  // ---------- Внутреннее ----------

  Future<_ExportContext> _loadContext(List<Note> selection) async {
    if (selection.length > maxNotes) {
      throw ArgumentError('export selection is too large');
    }
    final projectNames = <String, String>{};
    for (final project in await db.select(db.projects).get()) {
      projectNames[project.id] = project.name;
    }
    final tagRowsByNote = <String, List<Tag>>{};
    final audioByNote = <String, List<int>>{};
    final ids = selection.map((n) => n.id).toList(growable: false);
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final tagRows = await (db.select(db.noteTags).join([
        innerJoin(db.tags, db.tags.id.equalsExp(db.noteTags.tagId)),
      ])..where(db.noteTags.noteId.isIn(chunk))).get();
      for (final row in tagRows) {
        final link = row.readTable(db.noteTags);
        tagRowsByNote
            .putIfAbsent(link.noteId, () => [])
            .add(row.readTable(db.tags));
      }
      final audioRows =
          await (db.select(db.mediaAssets).join([
                innerJoin(
                  db.audioRecordings,
                  db.audioRecordings.assetId.equalsExp(db.mediaAssets.id),
                ),
              ])..where(
                db.mediaAssets.ownerNoteId.isIn(chunk) &
                    db.mediaAssets.deletedAtUtc.isNull(),
              ))
              .get();
      for (final row in audioRows) {
        final asset = row.readTable(db.mediaAssets);
        audioByNote
            .putIfAbsent(asset.ownerNoteId, () => [])
            .add(row.readTable(db.audioRecordings).durationMs);
      }
    }
    return _ExportContext(
      projectNames: projectNames,
      tagRowsByNote: tagRowsByNote,
      audioByNote: audioByNote,
    );
  }

  static String _titleOf(Note note) {
    final title = note.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final firstLine = note.documentPlainText.trim().split('\n').first.trim();
    return firstLine;
  }

  static String _statusLabel(Note note) =>
      note.status.db == 'done' ? 'Выполнено' : 'В работе';

  static String _formatUtc(int millis) => DateTime.fromMillisecondsSinceEpoch(
    millis,
    isUtc: true,
  ).toIso8601String();

  /// Тело заметки из delta-проекции: checklist -> `- [ ]`/`- [x]`,
  /// списки -> `-`/`1.`, embeds -> пометки.
  static String _renderBody(Note note) {
    PotokDocument document;
    try {
      document = PotokDocument.decode(note.documentJson);
    } on FormatException {
      return note.documentPlainText;
    }
    final lines = <String>[];
    final buffer = StringBuffer();
    for (final op in document.deltaOps) {
      final insert = op['insert'];
      if (insert is Map<String, Object?>) {
        if (insert.containsKey('image')) buffer.write('[изображение]');
        if (insert.containsKey('audio')) buffer.write('[аудио]');
        continue;
      }
      if (insert is! String) continue;
      final parts = insert.split('\n');
      for (var i = 0; i < parts.length; i++) {
        buffer.write(parts[i]);
        if (i < parts.length - 1) {
          final attributes = op['attributes'];
          final list = attributes is Map<String, Object?>
              ? attributes['list']
              : null;
          final prefix = switch (list) {
            'checked' => '- [x] ',
            'unchecked' => '- [ ] ',
            'bullet' => '- ',
            'ordered' => '1. ',
            _ => '',
          };
          lines.add('$prefix${buffer.toString()}');
          buffer.clear();
        }
      }
    }
    if (buffer.isNotEmpty) lines.add(buffer.toString());
    return lines.join('\n').trimRight();
  }
}

class _ExportContext {
  final Map<String, String> projectNames;
  final Map<String, List<Tag>> tagRowsByNote;
  final Map<String, List<int>> audioByNote;

  _ExportContext({
    required this.projectNames,
    required this.tagRowsByNote,
    required this.audioByNote,
  });

  /// Материализуется один раз: getter в цикле экспорта пересобирал бы Map
  /// на каждую заметку (O(n²)).
  late final Map<String, List<String>> tagsByNote = {
    for (final entry in tagRowsByNote.entries)
      entry.key: [for (final tag in entry.value) tag.name],
  };
}
