# ADR-006: Backup/restore — ZIP-контейнер с manifest, quarantine restore

Статус: принят (2026-07-16)

## Решение
Контейнер `*.potok-backup` (ZIP без шифрования):

```
manifest.json   — формат-версия, дата, счётчики, sha256 всех файлов, версия схемы БД
database.sqlite — снапшот через VACUUM INTO (не копия live db+WAL)
media/...       — файлы ассетов по relative_path
```

- Создание: снапшот → стриминг в temp-файл → проверка manifest/hash → atomic rename в целевое имя.
- Restore: распаковка в quarantine-каталог поколения → лимиты path/size/zip-bomb, запрет `..` → read-only open + `PRAGMA quick_check`, `foreign_key_check`, версия схемы → страховочная копия текущих данных → атомарное переключение активного поколения; откат при любой ошибке.
- Backup открытый текст; UI предупреждает (контракт 0.10.1).
- Экспорт (Markdown/CSV/JSON) — отдельная функция WP-06; CSV экранирует `= + - @` (formula injection).
