import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/infrastructure/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v1 database upgrades to v3 without product sessions', () async {
    final temp = await Directory.systemTemp.createTemp('potok_v1_upgrade');
    final file = File('${temp.path}${Platform.pathSeparator}potok.sqlite');
    final raw = sqlite3.open(file.path);
    raw.execute('''
      PRAGMA foreign_keys = ON;
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        color_argb INTEGER NOT NULL,
        icon TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at_utc INTEGER NOT NULL,
        updated_at_utc INTEGER NOT NULL,
        deleted_at_utc INTEGER,
        revision INTEGER NOT NULL DEFAULT 1
      );
      CREATE TABLE notes (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT REFERENCES projects(id),
        title TEXT,
        status TEXT NOT NULL DEFAULT 'in_work',
        document_json TEXT NOT NULL,
        document_plain_text TEXT NOT NULL,
        source_kind TEXT NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        favorited_at_utc INTEGER,
        completed_at_utc INTEGER,
        event_at_utc INTEGER,
        created_at_utc INTEGER NOT NULL,
        updated_at_utc INTEGER NOT NULL,
        deleted_at_utc INTEGER,
        revision INTEGER NOT NULL DEFAULT 1
      );
      INSERT INTO projects (
        id, name, color_argb, created_at_utc, updated_at_utc
      ) VALUES ('p1', 'Существующий проект', 0, 1, 1);
      INSERT INTO notes (
        id, project_id, document_json, document_plain_text, source_kind,
        created_at_utc, updated_at_utc
      ) VALUES ('n1', 'p1', '{}', 'Существующая заметка', 'keyboard', 1, 1);
      PRAGMA user_version = 1;
    ''');
    raw.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });

    final version = await db
        .customSelect('PRAGMA user_version')
        .map((row) => row.read<int>('user_version'))
        .getSingle();
    expect(version, 4);
    final columns = await db
        .customSelect('PRAGMA table_info(notes)')
        .map((row) => row.read<String>('name'))
        .get();
    expect(columns, isNot(contains('session_id')));

    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row.read<String>('name'))
        .get();
    expect(tables, contains('smart_views'));
    expect(tables, isNot(contains('sessions')));
    final note = await db.select(db.notes).getSingle();
    expect(note.id, 'n1');
    expect(note.documentPlainText, 'Существующая заметка');
    final firstWord = note.documentPlainText.split(' ').first;
    expect((await db.searchNotes('"$firstWord"*', 10).get()).single.n.id, 'n1');

    final indices = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .map((row) => row.read<String>('name'))
        .get();
    expect(
      indices,
      containsAll([
        'idx_notes_live_created',
        'idx_notes_live_updated',
        'idx_notes_live_event',
        'idx_notes_live_title',
        'idx_notes_trash_deleted',
      ]),
    );
  });

  test('v2 session context is removed without deleting its notes', () async {
    final temp = await Directory.systemTemp.createTemp('potok_v2_upgrade');
    final file = File('${temp.path}${Platform.pathSeparator}potok.sqlite');
    final raw = sqlite3.open(file.path);
    raw.execute('''
      PRAGMA foreign_keys = ON;
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        color_argb INTEGER NOT NULL,
        icon TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at_utc INTEGER NOT NULL,
        updated_at_utc INTEGER NOT NULL,
        deleted_at_utc INTEGER,
        revision INTEGER NOT NULL DEFAULT 1
      );
      CREATE TABLE sessions (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT NOT NULL REFERENCES projects(id),
        title TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'active',
        started_at_utc INTEGER NOT NULL,
        ended_at_utc INTEGER,
        created_at_utc INTEGER NOT NULL,
        updated_at_utc INTEGER NOT NULL,
        deleted_at_utc INTEGER,
        revision INTEGER NOT NULL DEFAULT 1
      );
      CREATE TABLE notes (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT REFERENCES projects(id),
        session_id TEXT REFERENCES sessions(id) ON DELETE SET NULL,
        title TEXT,
        status TEXT NOT NULL DEFAULT 'in_work',
        document_json TEXT NOT NULL,
        document_plain_text TEXT NOT NULL,
        source_kind TEXT NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        favorited_at_utc INTEGER,
        completed_at_utc INTEGER,
        event_at_utc INTEGER,
        created_at_utc INTEGER NOT NULL,
        updated_at_utc INTEGER NOT NULL,
        deleted_at_utc INTEGER,
        revision INTEGER NOT NULL DEFAULT 1
      );
      INSERT INTO projects (
        id, name, color_argb, created_at_utc, updated_at_utc
      ) VALUES ('p1', 'Проект', 0, 1, 1);
      INSERT INTO sessions (
        id, project_id, title, started_at_utc, created_at_utc, updated_at_utc
      ) VALUES ('s1', 'p1', 'Старый контекст', 1, 1, 1);
      INSERT INTO notes (
        id, project_id, session_id, title, document_json,
        document_plain_text, source_kind, created_at_utc, updated_at_utc
      ) VALUES (
        'n1', 'p1', 's1', 'Сохранённое название', '{}',
        'Содержимое сохраняется', 'keyboard', 1, 1
      );
      PRAGMA user_version = 2;
    ''');
    raw.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });

    final note = await db.select(db.notes).getSingle();
    expect(note.id, 'n1');
    expect(note.projectId, 'p1');
    expect(note.title, 'Сохранённое название');
    expect(note.documentPlainText, 'Содержимое сохраняется');
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row.read<String>('name'))
        .get();
    expect(tables, isNot(contains('sessions')));
    final columns = await db
        .customSelect('PRAGMA table_info(notes)')
        .map((row) => row.read<String>('name'))
        .get();
    expect(columns, isNot(contains('session_id')));
  });
}
