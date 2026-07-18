# WP-10 — встроенный ASR, реактивность, мобильная навигация и упрощение продукта

Статус: реализован и проверен, 2026-07-18.

## 1. Анализ замечаний

### 1.1. Модель по умолчанию и распознавание во время записи

В приложение уже встроен runtime `sherpa_onnx`, но model weights находятся
только во внешней папке. Минимальная официальная единая модель, покрывающая
русский и английский, — multilingual Whisper tiny. Её int8 encoder, decoder и
tokens занимают 103 609 903 байта (около 98,8 MiB). `tiny.en` не подходит,
поскольку распознаёт только английский. Готового официального sherpa-пака,
ограниченного только парой RU+EN, нет; две отдельные streaming-модели увеличат
размер и потребуют явного выбора языка до записи.

Решение:

- поставлять `sherpa-onnx-whisper-tiny` int8 как bundled default model;
- бинарные weights не хранить в обычном Git: локальная папка assets игнорируется,
  а проверяемый build script скачивает/копирует файлы и сверяет SHA-256;
- на первом запуске staged-copy устанавливает модель в managed storage и
  активирует её, если пользователь ещё не выбрал другую;
- пользовательская установка из папки и переключение модели сохраняются;
- для live preview recorder отдаёт PCM16 stream, параллельно формирует валидный
  WAV и раз в несколько секунд распознаёт законченный chunk локально. Это
  near-real-time preview, а durable финальная расшифровка остаётся отдельной
  полной ASR job после stop;
- сеть и серверный API в runtime приложения отсутствуют.

### 1.2. Windows recording start

Текущий WAV-профиль передаёт `AudioEncoder.pcm16bits` в файловый `start()`.
Windows backend различает `pcm16bits` (raw stream) и `wav` (контейнер), поэтому
конфигурация не соответствует расширению и последующей signature validation.
Кроме того, общий текст ошибки скрывает причину.

Решение: WAV записывается из PCM stream собственным bounded writer с заголовком,
который финализируется при stop; M4A сохраняет штатный file recorder. Ошибки
permission/device/unsupported format/platform start получают разные безопасные
сообщения без путей и содержимого заметки.

### 1.3. Необновляющиеся карточки и Android capture

`notesChangeProvider` использует `Stream<void>`. Все события представлены одним
значением `null`, поэтому Riverpod может подавить повторную `AsyncData(null)`.
Пагинация не перечитывается после update/create до смены раздела.

Решение: поток изменений выдаёт монотонный локальный revision. Один механизм
обновляет карточку после autosave и новый Android capture сразу после commit.

### 1.4. Уведомления

Только quick-capture использует compact SnackBar; остальные места создают
обычный `SnackBar`. Наличие action совместно с accessibility navigation может
также удерживать сообщение дольше заданного времени.

Решение: единая функция показывает все transient messages с шириной по тексту,
центровкой, максимумом по viewport и принудительным закрытием через 4 секунды.
Диалоги и длительный progress этим механизмом не заменяются.

### 1.5. Android UX

- «Готово» во время записи запускает текстовое сохранение вместо stop+publish;
- narrow layout всё ещё использует Drawer, хотя прототип задаёт нижние вкладки;
- widget показывает технический project label и стандартные кнопки.

Решение:

- «Готово» при активной записи выполняет stop, durable publish и закрытие;
- mobile bottom navigation: «Все», «Проекты», «Избранное», «Поиск»;
  экран проектов также содержит «Без проекта», корзину, создание проекта и
  переход в настройки — Drawer удаляется;
- widget состоит из двух равных branded-кнопок «Текст» и «Голос» без project
  label; обе entry point по-прежнему проходят через Flutter use cases.

### 1.6. Названия заметок

В схеме уже есть nullable `Note.title`, но UI его не использует. Маленькая
локальная генеративная модель для качественного summarization означает второй
runtime/model pack и непропорциональный рост релиза. Поэтому этот WP не называет
эвристику AI.

Решение: чистый локальный `TitleGenerator` выбирает первую содержательную фразу,
нормализует пробелы/служебные символы и ограничивает результат. Название
создаётся из текста, принятой или готовой аудиорасшифровки, показывается отдельно
и редактируется пользователем. Ручное непустое название автоматически не
перезаписывается.

### 1.7. Удаление сессий

Владелец продукта исключил режим встреч/сессий. Это принятое отклонение от
FR-SES и прежнего WP-04.

Решение: удалить Session из domain/application/UI/schema, убрать session link
из Note и миграцией v2→v3 сохранить сами заметки, отбросив только контекст
сессий. Старые backup v2 после restore проходят ту же миграцию. Термин
«сессия» остаётся только там, где обозначает техническую audio/network session,
а не продуктовую сущность.

### 1.8. Windows single-file

Штатная Flutter Windows release не является single-file: рядом с EXE нужны
Flutter engine, plugin DLL, ICU/data и assets (включая модель). Поддерживаемый
путь распространения — весь каталог Release либо installer/MSIX. Self-extracting
EXE технически возможен, но распаковывает файлы при запуске и не является
настоящим portable single binary; в этот WP он не входит.

## 2. Порядок реализации

1. ADR/TZ: bundled model, near-live preview, локальные titles и удаление Session.
2. Исправить notes change revision и покрыть update/create regression tests.
3. Перевести WAV на PCM stream writer, добавить live preview и понятные ошибки;
   сделать «Готово» terminal action записи.
4. Добавить verified bundled tiny model bootstrap и сохранить external model UI.
5. Включить `Note.title`: генератор, ручное редактирование, карточки, ASR hook.
6. Унифицировать transient notifications и стабильную высоту selection header.
7. Реализовать mobile bottom navigation и обновить Android widget.
8. Удалить Session, выполнить schema v3 migration и обновить backup tests/TZ.
9. Targeted tests → полный `flutter test` → `flutter analyze` → release Windows
   и Android; зафиксировать размеры и device-only риски.

## 3. Acceptance criteria

- чистая установка распознаёт RU и EN без ручного выбора модели и без сети;
- внешнюю совместимую Whisper-модель можно установить и активировать как ранее;
- во время речи появляется локальный partial preview с честной chunk latency;
- Windows start создаёт валидный WAV и различает permission/device/platform
  failures; конкретные драйверы остаются частью device smoke;
- autosave меняет текст карточки без навигации, Android create появляется сразу;
- «Готово» во время записи останавливает и сохраняет её одной кнопкой;
- все transient messages компактны, центрированы и закрываются через 4 секунды;
- narrow layout имеет нижние четыре вкладки и не зависит от Drawer;
- widget содержит две оформленные кнопки без project label;
- заголовок создаётся локально, редактируется и не требует второй AI-модели;
- product Session отсутствует в UI, use cases и новой схеме; v2 notes сохранены;
- selection header не меняет высоту списка;
- Windows/Android release builds проходят, а runbook сообщает полный состав
  Windows-дистрибутива.

## 4. Итог реализации и проверки

- Встроены `sherpa_onnx 1.13.4` и официальный multilingual Whisper tiny int8;
  build assets закреплены SHA-256, bootstrap не заменяет пользовательский выбор.
- Нативный smoke отдельным Dart-процессом реально загрузил DLL/ONNX и обработал
  локальный WAV. Починен порядок `initBindings -> readWave`; для Windows host
  tool явно загружает совпадающий `onnxruntime.dll` 1.27.0.
- Windows PCM stream публикуется как валидный RIFF/WAV; live preview декодирует
  завершённые chunks примерно раз в 4 секунды. Почти тишина отсекается по RMS;
  финальный durable job остаётся авторитетной расшифровкой.
- `watchChanges()` выдаёт монотонные revision, поэтому autosave/create сразу
  инвалидируют карточки на Windows и Android.
- `Note.title` используется карточкой/detail; детерминированный локальный
  генератор поддерживает русский/английский и сохраняет ручное название.
- Все transient notifications переведены на compact floating UI и принудительно
  закрываются через 4 секунды; selection controls занимают фиксированную высоту.
- На narrow layout добавлен bottom tab bar; Android widget заменён двумя
  оформленными кнопками «Текст»/«Голос»; «Готово» финализирует активную запись.
- Продуктовая Session удалена из UI/domain/application и schema v3; миграционный
  тест подтверждает сохранность v2 notes.

Проверки: `dart analyze` — 0 issues; `flutter test` — 155 passed, 1 Windows
host-only smoke skipped (выполнен отдельной командой); Windows release — успешно;
universal и split-per-ABI Android release APK — успешно. Физический microphone/
widget/live-preview smoke на Windows-драйверах и Android-устройстве остаётся
обязательным перед публичным релизом.
