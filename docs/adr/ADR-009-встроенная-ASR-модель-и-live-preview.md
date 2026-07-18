# ADR-009 — встроенная ASR-модель и near-live preview

Дата: 2026-07-18  
Статус: принято

## Контекст

Offline ASR runtime уже основан на sherpa-onnx, но пользователь должен вручную
установить model pack. Продукту нужна рабочая модель из коробки, русский и
английский, а также видимая расшифровка во время речи.

## Решение

1. Bundled default — официальный multilingual Whisper tiny int8:
   encoder 12 937 772, decoder 89 855 401, tokens 816 730 байт.
2. Build input сверяется по закреплённым SHA-256. Бинарные weights не хранятся
   в обычном Git; release build обязан предварительно materialize assets.
3. First-run bootstrap копирует пак через staging в managed model storage и
   активирует только при отсутствии пользовательского выбора.
4. Пользовательские model packs остаются поддержаны тем же manifest/hash
   контрактом.
5. Recorder выдаёт PCM16/16 kHz mono chunks и одновременно пишет WAV. Whisper
   распознаёт завершённые chunks для UI preview; после stop durable queue
   распознаёт целый WAV и остаётся источником финальной ревизии.
6. Runtime не имеет downloader или server fallback.
7. Почти тишина отсекается дешёвым RMS gate до запуска Whisper. Это не заменяет
   VAD, но предотвращает очевидные hallucinations на пустых chunks без второй
   модели и новых permissions.

## Последствия

- размер установочного пакета вырастает примерно на 98,8 MiB;
- модель multilingual, поскольку официальной tiny-модели только RU+EN нет;
- preview имеет latency в несколько секунд и может отличаться от финального
  full-file результата;
- запись PCM16 занимает около 110 MiB/ч;
- для реального streaming token-by-token в будущем можно добавить отдельную
  online-модель, но это не блокирует текущий offline pipeline.
