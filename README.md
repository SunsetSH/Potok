# Поток

Локальное приложение для быстрых заметок: голос, текст, изображения. Голосовые записи расшифровываются **на устройстве** нейросетевой ASR-моделью (Whisper через sherpa-onnx) — без облака и без передачи данных наружу.

Платформы: **Windows**, **Android**. Стек: Flutter, Riverpod, Drift (SQLite), flutter_quill, sherpa-onnx.

## Возможности

- 🎙️ **Голосовые заметки** — запись с микрофона, устойчивая к прерываниям; расшифровка офлайн (Whisper tiny встроена, более крупные модели скачиваются в менеджере моделей)
- 📝 **Rich-текст редактор** (flutter_quill): форматирование, списки, inline-изображения (вставка из буфера обмена)
- 🗂️ **Проекты и теги** — заметки группируются по проектам, фильтры и умные представления (smart views)
- 🗑️ **Корзина** — мягкое удаление с восстановлением
- 💾 **Резервное копирование** — бэкап и восстановление с карантином повреждённых данных
- 📤 **Экспорт** в Markdown, CSV и JSON
- 🎨 **4 темы оформления**, трёхпанельный интерфейс на десктопе
- ⚡ **Быстрый ввод**: системный трей и глобальный hotkey на Windows, виджет быстрой записи на Android
- 🔒 **Приватность**: все данные хранятся локально в SQLite

## Структура репозитория

```
app/            Flutter-приложение
  lib/domain          модель документа, типы
  lib/application     сервисы (заметки, теги, бэкап, экспорт, очередь расшифровки)
  lib/infrastructure  БД (drift), ASR, аудиозапись/плеер
  lib/presentation    UI (Riverpod)
  test/               тесты
  tool/               скрипты подготовки ASR-модели и релиза
docs/           ТЗ, work packages, ADR (архитектурные решения)
```

## Запуск

### Требования

- [Flutter](https://docs.flutter.dev/get-started/install) **3.44+** (версия зафиксирована в `app/.flutter-version`)
- Windows: Visual Studio 2022 с workload «Desktop development with C++»
- Android: Android SDK (через Android Studio), NDK

### Подготовка

```powershell
cd app

# Скачать и проверить встроенную ASR-модель Whisper tiny (обязательно, это build input)
powershell -ExecutionPolicy Bypass -File tool/prepare_default_asr_model.ps1

flutter pub get
```

### Запуск в режиме разработки

```powershell
flutter run -d windows    # Windows
flutter run -d <device>   # Android (flutter devices — список устройств)
```

### Сборка релиза

```powershell
# Windows
flutter build windows --release
# результат: build/windows/x64/runner/Release/

# Android (arm64 — компактный APK для современных устройств)
flutter build apk --release --target-platform android-arm64 --split-per-abi
# результат: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### Тесты

```powershell
flutter test
```

## Архитектура

Слоистая архитектура: `domain` → `application` → `infrastructure` / `presentation`. Ключевые решения задокументированы в [docs/adr/](docs/adr/): выбор Flutter, sherpa-onnx для ASR, Drift/SQLite как хранилище, формат документа, схема backup/restore, sync-ready модель данных.

## Лицензия

См. [LICENSE](LICENSE).
