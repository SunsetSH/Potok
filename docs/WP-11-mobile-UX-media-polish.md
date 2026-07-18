# WP-11 — mobile UX, media polish и вставка изображений

Статус: реализовано; Windows release ожидает закрытия запущенного EXE  
Дата: 2026-07-18

## 1. Область и требования

Пакет уточняет `FR-NOT-001`, `FR-DOC-003`, `FR-AUD-001`, `FR-MOV-003..005`,
`FR-SRC-007`, `FR-PRJ-001` и Android bottom navigation из ТЗ. Инварианты не
меняются: Android остаётся первичным, Windows обязательным, изображения —
managed media, обработка буфера и ASR не используют сеть.

## 2. Анализ дефектов и решения

### 2.1. Android widget

Compound drawable и подпись имеют `drawablePadding=8dp`, поэтому содержимое
визуально распадается на две части. Уменьшить интервал до 4 dp, убрать лишний
font padding и сохранить центрирование compound content. Подписи — `+Текст` и
`+Аудио`; default resources получают эквиваленты `+Text` и `+Audio`.

### 2.2. Фокус mobile navigation и список проектов

Поиск использует один долгоживущий `FocusNode`. Повторный `requestFocus()` не
показывает IME, если node уже focused, а переходы в другие разделы не снимают с
него фокус. Все непоисковые destination явно снимают только search focus.
Destination «Поиск» выполняет re-focus и повторно просит системный text input
показать IME после кадра.

Шторка проектов сейчас читает `projectsProvider` один раз до `showModalBottomSheet`,
поэтому новый проект не попадает в уже открытый список. Содержимое шторки
переводится на `Consumer` с `watch`; создание/редактирование проекта также явно
инвалидирует справочники после commit. Перед modal move flow search focus
снимается, чтобы закрытие шторки не восстанавливало клавиатуру.

### 2.3. Цвета, фильтры и выделение текста

Отдельные палитры проектов и тегов содержат близкие синие/фиолетовые пары.
Ввести одну общую палитру из 16 различимых цветов: blue, orange, red, teal,
green, purple, amber, slate, magenta, cyan, olive, brown, pink, indigo, lime и
deep orange. Имя/значок остаются обязательным нецветовым носителем смысла.

Кнопка сброса больше не занимает отдельную фиксированную область поверх ряда:
все chips, включая reset, находятся в одном горизонтально прокручиваемом ряду.
Selection overlay получает полупрозрачный accent, чтобы glyph foreground не
терялся в светлых и тёмных темах.

### 2.4. Запись и воспроизведение

Recorder adapter уже выдаёт нормализованную амплитуду, но UI показывает одно
статическое значение. Capture хранит ограниченное окно уровней и рисует
движущуюся waveform-полосу. Это индикатор амплитуды, а не FFT-анализ частот:
он одинаково работает для WAV и M4A и не хранит/не логирует микрофонные данные.

Windows seek защищается от несогласованных событий position/duration:
presentation использует bounded position, а controller сбрасывает position при
open/completed и принимает более частые position updates. Добавляется unit/widget
регрессия для середины записи и seek.

### 2.5. Изображения при capture и редактировании

Кнопка «Прикрепить фото» использует существующий picker и managed-media pipeline.
Для Ctrl+V вводится отдельный clipboard adapter на `pasteboard` по ADR-011. Изображение читается
только после явного paste, ограничивается 10 МБ, проверяется по magic bytes и
публикуется через staging → hash → atomic rename → DB ready. Обычный текстовый
paste сохраняется.

В quick capture выбранные изображения остаются локальным draft state. При
«Готово» сначала создаётся заметка, затем assets и image nodes публикуются
последовательно. При частичном отказе заметка не теряется, успешные вложения
остаются, а UI честно сообщает о неприкреплённых файлах. Пустая заметка без
текста и без изображения по-прежнему запрещена.

## 3. ASR-кандидаты, без смены default

Текущий multilingual Whisper tiny int8 остаётся встроенным до решения владельца.
Кандидаты оцениваются на одном локальном RU/EN corpus с шумом, именами и длинной
речью; сравниваются WER/CER, real-time factor, peak RAM и размер bundle.

1. Whisper base int8 — наименее рискованная замена в существующем adapter;
   около 161 МБ model files, умеренное увеличение качества/веса.
2. Whisper small int8 — тот же adapter, около 375 МБ model files; вероятно лучше
   на сложной речи, но требует device benchmark по RAM и скорости.
3. NVIDIA Multilingual FastConformer CTC int8 — RU/EN входят в 10 языков;
   streaming-friendly, но нужен новый model profile и проверка качества именно
   на разговорном русском.
4. NVIDIA Parakeet TDT 0.6B v3 int8 — RU/EN входят в 25 европейских языков,
   около 640 МБ; сильный кандидат для desktop/high-end устройств, слишком тяжёл
   для базового APK без отдельного model pack.
5. Двухмодельный pack: GigaAM v2 CTC int8 для русского плюс компактная English
   model. Потенциально сильнее по русскому, но требует явного/автоматического
   language routing, двух runtime profiles и отдельной лицензионной проверки.
   Доступные sherpa GigaAM packs имеют non-commercial ограничения, поэтому это
   не кандидат в коммерческий default без иной лицензии.

Официальные источники для решения:

- Whisper base int8: <https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/tree/main>;
- Whisper small int8: <https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/tree/main>;
- multilingual FastConformer: <https://k2-fsa.github.io/sherpa/onnx/lazarus/generate-subtitles.html#nemo-transducer>;
- Parakeet TDT v3: <https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-transducer/nemo-transducer-models.html>;
- Russian GigaAM и лицензии: <https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-ctc/nemo/russian.html>.

## 4. Порядок реализации

1. Widget resources, focus lifecycle и реактивная projects sheet.
2. Общая палитра, scrollable reset chip, selection overlay.
3. Rolling waveform и playback position regression.
4. Clipboard adapter, byte-safe image attach, picker/paste в capture и detail.
5. Targeted tests → полный `flutter test` → `dart analyze` → Windows/Android
   release builds; device smoke фиксируется отдельно.

## 5. Критерии приёмки

- widget визуально центрирован и подписан `+Текст`/`+Аудио`;
- повторное нажатие «Поиск» всегда показывает клавиатуру, а остальные переходы
  и move flow её не открывают;
- созданный проект появляется в открытой шторке без повторного входа;
- проекты и теги используют один набор из 16 различимых цветов;
- reset chip не перекрывает фильтры при любой поддерживаемой ширине;
- во время записи waveform реагирует на уровень сигнала;
- Windows slider показывает начало, середину и конец, seek меняет позицию;
- picker и Ctrl+V прикрепляют JPG/PNG/WebP в capture и detail через managed media;
- обычный текстовый Ctrl+V не ломается, неподдерживаемые/большие данные дают
  безопасную ошибку без пользовательских путей в логах;
- targeted/full tests, analyzer и обе release builds имеют зафиксированный итог.

## 6. Итог реализации и проверки

- widget: compound gap 4 dp, центрирование, `+Текст`/`+Аудио`;
- mobile navigation: non-search destinations снимают search focus, повторный
  Search делает re-focus и `TextInput.show`; projects sheet смотрит live stream;
- move flow снимает search focus до modal route;
- одна палитра из 16 цветов используется проектами и тегами;
- reset chip расположен первым в общем scrollable row и не перекрывает chips;
- selection overlay использует accent с alpha 0.22/0.32;
- capture рисует rolling amplitude waveform; player подписан на frequent
  position/discontinuity events и синхронно обновляет thumb при seek;
- picker и Ctrl+V используют durable hidden image draft, managed media staging,
  magic/size validation и publish с проверкой ready owner assets;
- `pasteboard 0.5.0` выбран после отрицательного build spike
  `super_clipboard 0.9.1` на Gradle 9;
- `dart analyze lib test`: 0 issues;
- `flutter test`: 159 passed, 1 штатно skipped native ONNX smoke;
- повторные targeted tests после смены clipboard adapter: 12 passed;
- Android release: успешно, `build/app/outputs/flutter-apk/app-release.apk`,
  209 361 003 bytes (debug signing по release runbook);
- Windows C++/plugin compilation дошла до link, но `potok.exe` PID 19884 держит
  release target открытым: `LNK1104`. После закрытия приложения повторить
  `flutter build windows --release`; это внешний file lock, не compile defect.

## 7. Корректирующий этап WP-11.1

Дата: 2026-07-18

По результатам device smoke выявлены регрессии, которые не ловятся
только fake-adapter тестами:

1. Исправить clipboard contract: определять фактический формат по magic
   bytes, принимать Windows DIB/BMP и копированные image files, сохранить
   лимит 10 МБ до чтения файла.
2. Вынести «Сбросить» в отдельную строку над горизонтальным списком
   quick filters.
3. После загрузки audio выполнять backend seek в ноль и игнорировать
   запоздалое end-position event в completed/paused state.
4. Добавить в note card явные actions «Избранное» и «Выполнено/в работу»
   с теми же атомарными application commands, что detail pane.
5. Заменить compound drawable Android widget на отдельные `ImageView`/`TextView`
   в центрированном контейнере с явным gap 3 dp.
6. Для PCM recording считать RMS-амплитуду из самих PCM chunks; для
   encoded recording сохранить platform amplitude stream. Waveform должен
   обновляться на каждом sample.
7. Добавить unit/widget regressions, затем повторить analyzer, полные tests и
   release builds.

Для ASR отдельно фиксируется точная оценка bundle growth Whisper small
и feasibility Qwen3-ASR 0.6B int8 через уже используемый sherpa-onnx;
default model в этом этапе не меняется.

### 7.1. Размер Whisper small и feasibility Qwen3-ASR

Текущий bundled Whisper tiny int8 занимает 103 610 427 байт в
`assets/models/default` (включая manifest). Для Whisper small int8 нужны
`small-decoder.int8.onnx` 262 МБ, `small-encoder.int8.onnx` 112 МБ и tokens
около 0,817 МБ: всего около 374,8 МБ. Замена tiny на small добавит
примерно 271,2 МБ к release bundle. При текущем APK 209 361 107 байт
проекция — около 480–485 МБ, но это расчёт, а не фактическая сборка.
После первого запуска текущий installer копирует bundled pack в app data,
поэтом полный рост занятого места может достичь ещё примерно
271 МБ в user data. Для small рациональнее downloadable optional pack, а не
замена в base APK.

Qwen3-ASR теперь технически интегрируем без второго inference runtime:
используемый Potok `sherpa_onnx 1.13.4` уже содержит Dart
`OfflineQwen3AsrModelConfig`. Официально опубликованный sherpa-onnx pack
Qwen3-ASR-0.6B int8 состоит из conv frontend 42 МБ, decoder 721 МБ,
encoder 174 МБ и tokenizer около 4,2 МБ: около 941 МБ без test WAV.
Модель Apache-2.0, поддерживает Russian/English и ещё 28 языков.

Вывод:

- сделать Qwen3-ASR отдельным скачиваемым high-quality pack, не
  встраивать в base APK;
- расширить model manifest типом `qwen3_asr` и путями frontend/encoder/
  decoder/tokenizer, после чего добавить ветку в recognizer adapter;
- перед продуктовым выбором измерить RTF, peak RAM, cold model load и
  battery на среднем Android-устройстве и Windows CPU;
- sherpa пока предлагает для Qwen3-ASR simulated streaming с VAD; это не
  следует выдавать за гарантированную дешёвую true-streaming работу
  на любом телефоне.

Официальные источники:

- Qwen3-ASR project/license/languages: <https://github.com/QwenLM/Qwen3-ASR>;
- original 0.6B model size: <https://huggingface.co/Qwen/Qwen3-ASR-0.6B-hf/tree/main>;
- sherpa-onnx Qwen3 int8 pack/files/usage: <https://k2-fsa.github.io/sherpa/onnx/qwen3-asr/pretrained.html>;
- sherpa-onnx release with Dart/Qwen3 support: <https://github.com/k2-fsa/sherpa-onnx/releases>.

### 7.2. Итог WP-11.1

- clipboard adapter определяет PNG/JPEG/WebP/BMP по magic bytes; Windows
  Explorer file-list и DIB/BMP поддержаны, лимит 10 МБ проверяется до
  чтения copied file;
- кнопка сброса фильтров занимает отдельную зарезервированную
  строку над scrollable quick filters; search/bulk toolbar остаются одной
  фиксированной высоты;
- Windows audio controller после `setFilePath` выполняет backend seek/pause в
  ноль и отбрасывает EOF event в completed/paused state;
- note cards имеют быстрые favorite и done/in-work actions с реальными
  `NotesService` commands и privacy-safe error diagnostics;
- Android widget использует separate 18 dp `ImageView` + `TextView` с gap 3 dp;
- WAV/PCM capture рисует waveform по RMS тех же PCM chunks, которые
  записываются в файл; encoded capture сохраняет platform amplitude stream;
- `dart analyze lib test`: 0 issues;
- targeted regressions: 20 + 2 card-action tests passed;
- full `flutter test`: 164 passed, 1 штатно skipped native ONNX smoke;
- Android release: успешно через ASCII junction, APK 209 361 107 байт;
- Windows release: успешно, Release directory 164 871 647 байт;
- device smoke нового clipboard/playback/waveform/widget после этой сборки
  остаётся ручной проверкой на целевых Windows/Android устройствах.
