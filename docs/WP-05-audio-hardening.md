# WP-05: audio hardening

Статус: завершён и верифицирован владельцем продукта (2026-07-18).

## Реализованный срез

- Без активной ASR-модели `record` пишет AAC-LC/M4A, mono, 44.1 kHz; качество 48/64/96 kbit/s выбирается в настройках. При активной локальной модели новая запись создаётся как WAV PCM16, mono, 16 kHz и сразу пригодна для offline ASR. Оценка размера — 21/28/42 MB на час для M4A и около 110 MiB/ч для WAV (FR-AUD-009/014, ADR-005).
- Пауза, продолжение, stop, cancel, таймер, индикатор уровня и настраиваемый лимит 10/30/60/120 минут (FR-AUD-002/003/008).
- Перед start проверяется место для всего заданного лимита плюс 8 MiB. Во время записи свободное место обновляется раз в 5 секунд; на 8 MiB запись корректно завершается (FR-AUD-003/005).
- Android: microphone foreground service, ongoing notification, `foregroundServiceType="microphone"`, `POST_NOTIFICATIONS`, keep-screen-on. Windows: `SetThreadExecutionState` на время записи. Оба адаптера также отдают свободное место (FR-AUD-004).
- На Windows настройки показывают capture devices из `record`, сохраняют выбранный device ID в `app_meta` и не подменяют исчезнувшее устройство системным default без сообщения пользователю.
- Финализация проверяет M4A/WAV signature, size и SHA-256, затем делает atomic rename и DB publish. Пути с `..`/абсолютные пути отвергаются (FR-AUD-002/006, ADR-004).
- До atomic rename в hidden staging сохраняются duration/codec/sample rate/channels и коммент. Startup repair может закончить publish до или после rename.
- Repair сверяет `ready`/`missing` с файлами и hash, восстанавливает статус только при том же SHA-256, убирает stale staging и orphan `.partial`.
- Плеер `just_audio` + `audio_session` + `just_audio_windows`: seek, ±10 с, 0.75/1/1.25/1.5/2x, focus/interruption, keyboard-accessible slider. Режим ручной расшифровки ставит playback на паузу и возвращает фокус в editor (FR-AUD-011/012).
- Схема и use cases допускают нескольо независимых audio assets на note. Detail показывает отдельный плеер/сумму/hash lifecycle и даёт добавить ещё (FR-AUD-013).
- Удаление audio — soft delete: файл остаётся. В настройках доступны restore и явный purge; purge оставляет DB tombstone для sync-ready модели (FR-AUD-003/007).
- Экран места показывает audio, images, trash, missing count и свободное место. Hard quota не вводится по решению WP-00.
- После durable publish аудио при активной локальной модели создаётся ASR job
  (FR-AUD-005). Сбой enqueue не откатывает уже готовое аудио: оно остаётся
  доступным для явного retry.

## Проверки

До среза multiple attachments/soft-delete выполнено:

- `dart analyze` — без замечаний;
- 58 затронутых media/audio/UI тестов — passed;
- отдельные tests AAC recording, low storage и storage usage — passed;
- `flutter build windows --debug` — passed;
- `flutter build apk --debug` — passed.

Последний срез (multiple attachments, audio trash/restore/purge) прогнан 2026-07-17: `flutter analyze` — 0 issues, `flutter test` — 121/121, `flutter build windows --debug` и `flutter build apk --debug` — успешно. Остаётся ручной device smoke (см. ниже).

## Device/release regression matrix

Эти сценарии остаются обязательными повторяемыми smoke-проверками каждого release,
но не являются незакрытыми задачами WP-05: Android background 30+ мин,
notification permission denied/granted, incoming call, Bluetooth/headset disconnect, low storage;
Windows record/play M4A, sleep inhibition и microphone privacy denial.
