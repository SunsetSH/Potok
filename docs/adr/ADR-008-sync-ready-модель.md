# ADR-008: Sync-ready модель без сервера в MVP

Статус: принят (2026-07-16)

## Решение
MVP полностью локален, но схема готовится к будущей синхронизации (ТЗ 0.12):

- Все сущности: UUIDv7, `revision`, UTC-времена, tombstone через `deleted_at_utc` (запись не выпиливается физически до очистки корзины).
- `OperationJournal` пишется с первого дня для мутаций заметок/проектов/тегов: `operation_id`, `device_id`, entity ref, `base_revision`, `new_revision`, `operation_kind`, время, минимальный payload. Идемпотентность retry — по `operation_id`.
- `device_id` генерируется при первом запуске и хранится локально.
- History (`NoteEvent`) — append-only.
- Сервер, аккаунты, конфликт-merge UI — вне скоупа; проектируются отдельным ADR перед WP-sync.

Запрещено: совместное открытие live SQLite через облачную папку.
