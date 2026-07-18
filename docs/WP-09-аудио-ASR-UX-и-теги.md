# WP-09 — микрофоны Windows, рабочий offline ASR, UX списка и пользовательские теги

Статус: реализован и верифицирован автоматическими проверками, 2026-07-18.

Дополнение: bundled model, PCM-stream WAV writer и near-live preview из WP-10 /
ADR-009 заменяют описанный ниже промежуточный контракт ручной установки модели.

## 1. Результат анализа

### 1.1. Запись и выбор микрофона

`record 7.1.1` и его Windows backend уже предоставляют
`listInputDevices()` и `RecordConfig.device`. Текущий `AudioRecorderPort` эти
возможности скрывает и всегда открывает системное устройство по умолчанию.
Поэтому при неверном default input, отключённой гарнитуре или виртуальном
устройстве запись либо не стартует, либо пишет не тот источник.

Решение:

- расширить adapter contract типом `AudioInputDevice` и операцией перечисления;
- хранить выбранный Windows device ID в `app_meta`, значение `null` означает
  «системный по умолчанию»;
- перед start разрешать сохранённый ID только через свежий список устройств;
- исчезнувшее устройство не подменять молча другим: показать ошибку и дать
  выбрать default/другой микрофон;
- добавить выбор и обновление списка в настройках аудио.

### 1.2. Offline ASR

В проекте уже есть `sherpa_onnx 1.13.4`, model manager, durable queue и
`SherpaWhisperRecognizer`. Движок не обращается к серверу, но рабочая цепочка
разорвана: recorder публикует AAC/M4A 44.1 kHz, а recognizer читает WAV/PCM.
Кроме того, UI требует заранее подготовленный `potok-model.json`, что слишком
сложно для обычной установки официальной модели.

Рассмотрены варианты:

1. **Оставить sherpa-onnx (выбран).** Apache-2.0, официальный Dart/Flutter
   binding, Windows и Android, уже изолирован adapter contract. Whisper code и
   weights — MIT. Нужны понятный импорт model pack и PCM-вход.
2. **whisper.cpp.** MIT, зрелый Windows/Android runtime, но потребует второго
   FFI-плагина, GGML-model manager и всё равно PCM16 input. Сейчас не устраняет
   корневой разрыв дешевле sherpa-onnx.
3. **Vosk.** Offline и сравнительно компактный, но отдельные platform bindings,
   и качество русского требуется заново сравнивать на продуктовом корпусе.
4. **FFmpegKit как декодер.** Не принимается: исходный проект retired; форки
   увеличивают binary/licensing/supply-chain поверхность.

Первая рабочая стратегия:

- если активна проверенная локальная модель, новая запись создаётся как WAV,
  PCM16, mono, 16 kHz и сразу подходит sherpa-onnx;
- если модели нет, остаётся компактный AAC/M4A baseline;
- WAV занимает около 110 MiB/час против ~28 MiB/час у M4A 64 kbit/s — это
  явно показывается в настройках;
- старые M4A остаются воспроизводимыми; их ASR требует будущего native
  `AudioDecodePort` (Media Foundation / MediaCodec), без FFmpeg dependency;
- приложение само сеть не получает. Модель скачивается пользователем отдельно
  с официального источника и импортируется из локальной папки;
- импорт официальной Whisper-папки выбирает int8 encoder/decoder и tokens,
  копирует их через staging, вычисляет SHA-256 и создаёт внутренний manifest;
  повторная activation сверяет hashes. Первый trust anchor — выбранный
  пользователем архив; release runbook требует сверить его с официальным
  `checksum.txt`.

Источники решения:

- sherpa-onnx: https://github.com/k2-fsa/sherpa-onnx
- официальные Whisper ONNX models:
  https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/index.html
- Whisper license: https://github.com/openai/whisper/blob/main/LICENSE
- whisper.cpp: https://github.com/ggml-org/whisper.cpp

### 1.3. Список заметок, фильтры и drag-and-drop

- «Сбросить» находится последним элементом горизонтального scroll и визуально
  обрезается. Он станет фиксированным action справа от scrollable quick chips.
- В карточке checkbox сейчас занимает первое и самое заметное место, а действие
  переноса — малозаметная иконка. Текст переносится наверх; checkbox становится
  вторичным trailing control; проект и явная кнопка «В проект» — в нижней
  metadata-строке.
- Desktop drag формально реализован через `LongPressDraggable`, поэтому обычный
  mouse drag не начинается. На широком Windows layout используется обычный
  `Draggable`; long press и кнопочная альтернатива сохраняются для узкого UI.

### 1.4. Сообщения

Floating SnackBar имеет форму, но не ограниченную ширину. Сообщение о сохранении
быстрой заметки станет компактным: ширина рассчитывается по тексту, ограничена
доступным окном и центрируется.

### 1.5. Теги

Модель и `TagsService.createTag()` уже поддерживают global/project scope, но UI
умеет только назначать предустановленные теги. Нет update use case.

Решение:

- добавить `updateTag()` с журналом операции, нормализацией и уникальностью;
- scope существующего тега не менять: перенос global↔project может сделать
  текущие note-tag связи недопустимыми и требует отдельной миграции;
- добавить менеджер тегов в настройки: создание global или project tag,
  изменение имени/цвета;
- в detail-панели действие `+ тег` также предлагает «Создать тег…», после чего
  новый тег назначается текущей заметке;
- имя 1…60 символов, цвет не является единственным носителем смысла.

## 2. Порядок реализации

1. Аудиопорт, device setting и Windows microphone selector; тесты default,
   выбранного и исчезнувшего устройства.
2. ASR-ready WAV profile, импорт официальной sherpa Whisper directory,
   совместимость manifest/hash/license и end-to-end queue tests.
3. Фиксированный reset, обновлённая карточка, desktop drag и compact SnackBar;
   widget tests на layout/actions.
4. Tag update use case и UI создания/редактирования global/project tags;
   domain/integration/widget tests.
5. Targeted tests → полный `flutter test` → `flutter analyze` → release builds
   Windows и Android. Device-only риски записываются, но не выдаются за
   проверенные без устройства.

## 3. Acceptance criteria

- Windows показывает реальные capture devices, помнит выбор и записывает через
  выбранный ID; missing device даёт понятную ошибку без записи.
- При активной модели новая WAV-запись доходит до `TranscriptRevision.ready`
  полностью offline; без модели текст и M4A-запись продолжают работать.
- Модель нельзя активировать при несовместимом engine/type или несовпадающем
  SHA-256.
- Reset полностью видим при ширине списка из скриншота.
- Mouse drag карточки на проект работает без удержания; кнопочный путь остаётся.
- Текст — первый визуальный уровень карточки, перенос в проект имеет явную
  подписанную кнопку.
- Save SnackBar центрирован и не растягивается на окно.
- Пользователь создаёт global/project tag и редактирует его имя/цвет; project
  tag нельзя назначить заметке другого проекта.

## 4. Сборка и артефакты

Из `app/`:

```powershell
flutter pub get
flutter test
flutter analyze
flutter build windows --release
flutter build apk --release
```

Артефакты:

- Windows: `app/build/windows/x64/runner/Release/potok.exe` и соседние DLL/data;
- Android APK: `app/build/app/outputs/flutter-apk/app-release.apk`;
- для Play после настройки production signing:
  `flutter build appbundle --release`, результат
  `app/build/app/outputs/bundle/release/app-release.aab`.

Release APK проекта пока допускает debug signing только для QA, не для
публикации. Полный release runbook остаётся в `docs/WP-07-релиз.md`.

## 5. Установка локальной модели

1. Скачать и распаковать совместимую Whisper-модель из официального каталога
   sherpa-onnx. Для первого запуска рекомендуется int8-вариант `tiny` или
   `base`; модель загружается пользователем вне приложения.
2. В «Настройки → Распознавание речи» нажать «Выбрать папку модели» и указать
   распакованный каталог с `encoder*.onnx`, `decoder*.onnx` и `tokens.txt`.
3. Приложение предпочитает int8-файлы, копирует только выбранные компоненты в
   managed storage через `.partial`, вычисляет SHA-256 и создаёт внутренний
   manifest. После активации новые записи создаются как WAV PCM16/16 kHz и
   автоматически попадают в durable ASR queue.

Приложение не скачивает модель и не обращается к серверу распознавания. Перед
импортом пользователь должен сверить архив и `checksum.txt` на официальной
странице модели. Старые AAC/M4A-записи остаются воспроизводимыми, но их
автоматическое распознавание потребует отдельного нативного `AudioDecodePort`.

## 6. Фактическая верификация

- `flutter analyze` — 0 issues;
- `flutter test` — 155/155;
- реальный offline spike на локальной sherpa Whisper tiny: русский WAV 6,62 с
  обработан за 0,67 с, английский WAV 4,39 с — за 0,46 с, RTF около 0,10;
- `flutter build windows --release` — успешно, 31 с;
- `flutter build apk --release` — успешно, 41 с, APK около 141,7 MiB;
- импорт папки модели, выбор int8-компонентов, hash/compatibility checks,
  выбранный microphone ID, WAV-профиль, узкий layout фильтров, drag и tag
  operations покрыты автоматическими тестами.

Ручной smoke на физическом микрофоне Windows и Android-устройстве остаётся
обязательным: автоматические тесты подтверждают передачу выбранного device ID,
но не могут доказать корректность конкретного драйвера, privacy permission,
Bluetooth-гарнитуры или реального аудиотракта. Flutter 3.44.6 также выдаёт
предупреждение о будущей несовместимости Kotlin Gradle Plugin у
`quill_native_bridge_android`; текущая release-сборка проходит.
