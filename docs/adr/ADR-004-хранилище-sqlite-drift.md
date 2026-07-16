# ADR-004: Хранилище — drift (SQLite) + FTS5, media в файлах

Статус: принят (2026-07-16)

## Решение
- `drift` поверх `sqlite3` (bundled native), общая схема Android/Windows, миграции drift.
- PRAGMA: `foreign_keys=ON`, `journal_mode=WAL`, `synchronous=NORMAL` в WAL (durability-компромисс фиксируется здесь; crash-тесты обязаны это подтвердить), bounded `busy_timeout`.
- Один логический writer: все мутации через единый исполнитель (drift сериализует запись); read — короткие snapshot-запросы; никаких внешних `await` внутри транзакции.
- Optimistic concurrency: `UPDATE ... WHERE id=? AND revision=?`; несовпадение — конфликт, не тихая перезапись.
- Пагинация keyset (по `(created_at, id)`), не OFFSET.
- ID: UUIDv7 (сортируемость), время UTC ISO-8601/epoch millis, soft delete через `deleted_at_utc`.
- FTS5-таблица (title, plain text, accepted transcript), синхронизация триггерами; RU-токенизация — `unicode61 remove_diacritics 2`, spike на морфологию отложен (FR-SRC-001).
- Media вне БД: `<app-data>/media/<xx>/<asset_id>.<ext>`; протокол финализации: DB `staging` → запись `<id>.partial` (тот же том) → flush/close → валидация → SHA-256 → atomic rename → DB `ready`. Reconciliation на старте: staging/orphan/ready+missing — без молчаливого удаления.

## Схема (MVP)
Таблицы из ТЗ 0.7: Project, Note, Tag, NoteTag, MediaAsset, AudioRecording, TranscriptRevision, NoteEvent, Draft, OperationJournal (+ Reminder, NoteLink, SmartView заготовками). Индексы — минимальный набор из 0.7.5.

## Отклонено
- BLOB media в SQLite (запрещено ТЗ), sqflite (нет desktop/FTS-гибкости), ObjectBox/Isar (нет SQL/FTS5).
