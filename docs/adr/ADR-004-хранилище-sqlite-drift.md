# ADR-004: Хранилище — drift (SQLite) + FTS5, media в файлах

Статус: принят (2026-07-16)

Дополнение 2026-07-18: часть schema v2 про продуктовую `Session` отменена
ADR-010. Schema v3 удаляет таблицу/ссылку с сохранением заметок; `SmartView`
остаётся. Ниже сохранена история решения v2, но она больше не нормативна для
актуальной схемы.

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

### Эволюция schema v2 (2026-07-17)

- Добавляются `Session`, `SmartView` и nullable `Note.session_id` (`ON DELETE SET NULL`) для WP-04.
- `Session` имеет `active/paused/completed`; частичный unique-индекс на константу при `state IN ('active','paused') AND deleted_at_utc IS NULL` гарантирует не более одной незавершённой сессии в локальном workspace даже при обходе application-слоя. Это исключает неоднозначное восстановление нескольких paused-контекстов.
- После process death `active` всегда восстанавливается как `paused`: открытие приложения не возобновляет микрофон или другую platform-работу.
- `SmartView` хранит имя и versioned JSON definition из allowlisted filter/sort enums. Пользовательский SQL, имя колонки или SQL-fragment не сохраняется и не исполняется.
- Редакция ТЗ 0.3 явно отменила обязательный `NoteType`; предустановленные «Вопрос/Риск/…» остаются глобальными тегами. Поэтому `NoteType/type_id` в v2 не добавляются, несмотря на устаревшие разделы 0.2 ниже нормативного блока.
- Upgrade `v1 -> v2` добавляет таблицы/nullable column/индексы и не переписывает существующие документы или media metadata. FTS virtual table и триггеры пересоздаются с совпадающим именем external-content column `document_plain_text`, затем выполняется штатный FTS5 `rebuild`; это исправляет drift-warning и сохраняет поиск по старым заметкам.
- Для списков добавлены keyset-индексы live created/updated/event/title и partial index корзины. UI получает страницы по 50 строк; sidebar использует отдельные агрегаты, выбранная заметка — точечный запрос по ID. Gate первой страницы проверяется на 50 000 строках с бюджетом 500 мс.
- Интерактивная массовая операция ограничена 500 выбранными заметками и атомарна в одной короткой локальной транзакции с optimistic revision каждого элемента. При одном stale element откатывается весь набор. Более крупный stress-case на 10 000 записей не должен расширять эту транзакцию: для него требуется отдельный resumable chunk/progress protocol с явно видимым промежуточным состоянием.

## Отклонено
- BLOB media в SQLite (запрещено ТЗ), sqflite (нет desktop/FTS-гибкости), ObjectBox/Isar (нет SQL/FTS5).
