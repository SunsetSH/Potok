# ADR-002: Локальный ASR — sherpa-onnx через adapter contract

Статус: принят, дополнен WP-09 (2026-07-18)

## Решение
- Движок по умолчанию: `sherpa-onnx` (плагин `sherpa_onnx`), offline-recognizer по записанному файлу.
- Доступ только через интерфейс `LocalSpeechRecognizer` (Dart abstract class); замена движка (whisper.cpp, Vosk) не трогает Application-слой.
- Полный benchmark-gate из ТЗ 0.3.3 выполняется при интеграции аудио (WP-03) на реальном RU/EN корпусе; ADR обновляется результатами.

## Model packs
- Модели не входят в дистрибутив. Загрузка/импорт отдельным менеджером.
- Манифест пакета: `model_id`, `engine`, `engine_min_version`, `languages`, `license`, `size_bytes`, `sha256` (по каждому файлу), `min_ram_mb`, `version`.
- Активация только после проверки hash и пробного открытия runtime.
- Профили: Compact (≤100 MB), Balanced (≤250 MB), Quality (Windows/мощный Android).

## Контракт (из ТЗ 0.3.1, обязателен)
- Состояния job: `queued, recognizing, ready, failed, cancelled, waiting_for_model`.
- Аудио сохраняется durable до запуска ASR; без модели работают текст и запись.
- Каждая попытка = новая `TranscriptRevision`; текст пользователя не заменяется без явного принятия.
- Никакого network client в runtime; airplane-mode тест обязателен.

## Конвейер
Recorder → сжатый исходник → декод в mono PCM 16 kHz → VAD/чанки → ASR → revision + timestamps → явное принятие в документ.

## Дополнение WP-09: рабочий PCM-вход до появления native decoder

- `sherpa-onnx` остаётся единственным ASR runtime; второй движок не добавляется.
- Новая запись при активной модели создаётся как WAV PCM16 mono 16 kHz и
  передаётся recognizer без промежуточного декодирования.
- Без активной модели сохраняется AAC/M4A. Для ASR старых M4A требуется будущий
  platform `AudioDecodePort` на Media Foundation / MediaCodec.
- Официальную Whisper ONNX directory разрешено импортировать без заранее
  созданного `potok-model.json`: installer выбирает int8 encoder/decoder и
  tokens, staging-копия хешируется, внутренний manifest фиксирует SHA-256 и
  лицензию. Сеть в runtime не добавляется.
- Это осознанный временный storage trade-off (~110 MiB/ч для WAV); исходное
  аудио по-прежнему сохраняется до явного удаления.
