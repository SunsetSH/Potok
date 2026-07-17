# WP-04: rich-document и inline images — статус подэтапа (2026-07-17)

## Граница подэтапа

Это не закрытие всего WP-04. Подэтап доводит существующий незавершённый переход с plain `TextField` на canonical Quill Delta, реализует базовый lifecycle inline-изображения и первый SQL-side срез расширенных списков. Нормативные источники: FR-DOC-001…004, FR-LST-003…007, FR-SRC-005…009, ADR-003 и ADR-004.

Новых архитектурных решений не принято: реализация следует уже принятым ADR-003 (Quill Delta в versioned envelope) и ADR-004 (SQLite metadata + managed media files). Зависимости `flutter_quill` и `file_selector` соответствуют этому решению.

## Реализовано

- detail-панель использует `QuillEditor` и ограниченный toolbar: undo/redo, bold, italic, strike, checklist, link и вставка изображения;
- canonical `PotokDocument` сохраняет rich Delta ops, строит plain-text projection для FTS и не включает embeds в проекцию;
- входные и выходные Delta ops глубоко копируются; malformed non-object ops отклоняются вместо частичного молчаливого чтения;
- выбранный PNG/JPEG/WebP до публикации проверяется по размеру, расширению и magic signature;
- изображение проходит `staging -> copy -> validate/hash -> atomic rename -> DB ready`; ожидаемый сбой финализации компенсирует staging-файл и строку БД;
- документ хранит только `asset://<asset_id>`, renderer разрешает только локальный ready asset и показывает privacy-safe placeholder при отсутствующем/повреждённом файле; сетевого fallback нет;
- image embed хранит редактируемые `alt` и `display` attributes; alt используется accessibility semantics, display переключается между wide и compact;
- startup reconciliation сканирует документы keyset-страницами по 500, сохраняет referenced assets, а unreferenced image старше 7 дней переводит в tombstone и идемпотентно очищает; любой повреждённый document JSON блокирует удаление fail-safe;
- локальная правка Quill, включая checkbox/embed, проходит через существующий debounce autosave и optimistic revision;
- перенос из detail-панели, Android long-press tray/кнопки и Windows drag/drop использует общий flow разрешения конфликтов project-тегов и undo; project list поддерживает controlled edge-autoscroll.
- список сортируется в SQLite по созданию, изменению, времени события, заголовку/первой строке и проекту в обоих направлениях; каждый вариант имеет стабильный tie-breaker по ID, а названия колонок выбираются только из enum allowlist;
- SQL-side фильтры комбинируют несколько проектов и «Без проекта», статусы, период создания, избранное, до 20 тегов в ANY/ALL-режиме и фактическое наличие ready audio/image/transcript rows;
- Android/Windows UI предоставляет адаптивную панель фильтров и сортировки, постоянно видимые быстрые/active chips, счётчик условий и «Сбросить»; FTS-результат пересекается с текущим разделом и SQL-фильтром, сохраняя выбранную сортировку.
- schema v2 аддитивно добавляет `Session`, `SmartView` и nullable `Note.session_id`; реальный upgrade v1→v2 сохраняет существующие заметки, а `ON DELETE SET NULL` не даёт удалению сессии уничтожить записи;
- сохранённое представление содержит только versioned JSON allowlisted filters/sort (до 64 KiB), создаётся из панели фильтров, показывается в sidebar и применяется без пользовательского SQL;
- сессия создаётся для проекта, имеет guarded `active/paused/completed`, operation journal и единственный незавершённый контекст на уровне partial unique index; startup recovery всегда переводит `active` в `paused`, не вызывая recorder;
- нижняя session bar показывает имя/длительность, pause/resume/complete и открывает session capture; текстовая и аудиозаметка получают project/session atomically при создании, а paused session блокирует новый capture.
- живые разделы и корзина читаются keyset-страницами по 50 строк без `OFFSET`; все пять сортировок имеют курсор по allowlisted значению и `id`, а project `NULL` стабильно остаётся последним;
- sidebar и окно переноса используют SQL-агрегаты `COUNT/GROUP BY`, выбранная заметка загружается по ID, undo не сканирует журнал, а FTS пересекает только ограниченный набор найденных ID на SQL-стороне — production UI больше не подписывается на полный список заметок;
- Drift change-stream инвалидирует загруженные страницы после любой мутации таблицы Notes; UI лениво догружает 50+ строк при приближении к концу списка;
- добавлены составные индексы для live created/updated/event/title и partial index корзины; gate первой страницы на реальной SQLite-базе из 50 000 заметок укладывается в 500 мс;
- FTS external-content column приведена к имени `document_plain_text`; upgrade v1→v2 безопасно пересоздаёт FTS/триггеры и делает `rebuild`, сохраняя поиск по существующим заметкам.
- bounded selection UI поддерживает до 500 заметок и атомарно меняет проект, глобальный тег, статус либо переносит весь выбор в корзину; optimistic conflict откатывает весь набор, project-теги при массовом переносе получают одно явное решение;
- история сессий доступна из sidebar и нижней панели: записи идут хронологически, показывают абсолютное локальное время и offset от старта; сессию можно переименовать и soft-delete, при этом заметки гарантированно сохраняются.
- поиск объединяет FTS5 body/title/transcript с параметризованным SQL-поиском по живым именам проектов и тегов; `%`, `_` и escape-символы пользовательского ввода экранируются, deleted metadata не участвует.

## Покрытие требований

- **FR-DOC-001:** выполнено для текущей версии canonical document envelope.
- **FR-DOC-002:** paragraph, bold, italic, strike, checklist, link, inline image и plain projection доступны; audio embed остаётся отдельным следующим подэтапом.
- **FR-DOC-003:** managed file, `asset_id`, редактируемые alt text/display attributes и локальный renderer выполнены.
- **FR-DOC-004:** checkbox является обычной Quill-операцией, участвует в undo и сохранении новой revision. Нужен отдельный widget/integration test реального toggle + process recreation.
- **FR-MOV-001…005:** desktop drag/drop, controlled edge-autoscroll, Android scrollable tray с target >= 56 dp, кнопочный эквивалент, conflict resolution, history transaction и undo выполнены.
- **FR-LST-003/004:** creation/update/event/title/project и ascending/descending выполнены; `NoteType` из старой редакции не реализуется, потому что нормативная редакция 0.3 его отменила.
- **FR-LST-005/006:** keyset pagination, lazy loading, стабильные tie-breakers, SQL-агрегаты и performance gate на 50 000 заметок выполнены для живых разделов и корзины.
- **FR-LST-007:** выбор сортировки работает, но пока хранится для общего UI-state, а не отдельно для каждого раздела и не переживает перезапуск.
- **FR-SRC-001/005/006/007/009:** FTS body/title/transcript, поиск по именам проектов/тегов, комбинируемые filters, ANY/ALL, active chips/reset и объяснение пустого результата выполнены.
- **FR-SRC-008:** создание и применение versioned saved view выполнено; rename/delete/reorder UI остаются следующим срезом.
- **FR-SES-001/002/005/008:** start с проектом/default title, автоматическая атомарная привязка session capture, crash recovery в paused и единственный open context выполнены.
- **FR-NOT-010:** массовые project/tag/status/trash операции выполнены для bounded UI selection до 500 записей одной транзакцией; stress-сценарий chunked operation progress для 10 000 записей остаётся release-hardening задачей.
- **FR-SES-003/004/007:** последовательный capture, абсолютное время/offset, rename и удаление контекста с сохранением заметок выполнены.
- **FR-SES-006:** pause/resume/complete/rename и просмотр хронологической лентой выполнены; целиковый session export остаётся в WP-06 вместе с общим экспортным adapter.

## Проверки

- `dart analyze` — без замечаний;
- целевые document/media/move/list-query/schema-v2/session/smart-view widget и integration tests — успешно;
- `flutter test` — 107/107;
- `flutter build windows --debug` — успешно, `build/windows/x64/runner/Debug/potok.exe`;
- `flutter build apk --debug` — успешно, `build/app/outputs/flutter-apk/app-debug.apk`.

Для Android в `android/gradle.properties` добавлен `android.overridePathCheck=true`: AGP по умолчанию блокировал Windows-сборку из каталога `Поток` до запуска компилятора. Реальная сборка с этим флагом успешна.

## Известные риски и следующий срез

1. Добавить widget/integration tests: внешний revision update, stale-save conflict и process recreation; базовый rich Delta/checklist autosave уже покрыт.
2. Расширить общий media repair на staging/ready+missing и неизвестные filesystem orphans; текущий срез безопасно обрабатывает DB-known image tombstones.
3. Продолжить WP-04: сохранение sort по разделам, управление saved views и передать session export в общий экспортный adapter WP-06. Поиск по проектам/тегам, базовые массовые операции, chronology и keyset performance gate закрыты; chunked progress для stress-case 10 000 записей остаётся hardening-задачей. `NoteType` не добавляется: нормативная редакция 0.3 его явно отменила в пользу тегов.
4. При обновлении Flutter проверить предупреждение Android-сборки: транзитивный `quill_native_bridge_android` пока применяет Kotlin Gradle Plugin старым способом; текущую сборку это не блокирует.
