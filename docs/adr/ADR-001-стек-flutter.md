# ADR-001: Платформенный стек — Flutter

Статус: принят (2026-07-16, решение владельца продукта)

## Контекст
ТЗ (0.8.1) предлагало .NET MAUI + spike против KMP/Compose. Требования: Android-приоритет, Windows обязателен, локальный ASR, rich-document JSON AST, соло-разработка.

## Решение
Flutter (stable, 3.44.x) + Dart, один код на Android и Windows.

## Обоснование
- Официальный плагин `sherpa_onnx` (основной ASR-кандидат из ТЗ) — готовый биндинг на обе платформы.
- Готовый rich-редактор с JSON AST (`flutter_quill`, Delta) — закрывает FR-DOC-001/002 без WebView.
- `drift` — SQLite + FTS5, миграции, изоляты.
- Экосистема закрывает: запись аудио (`record`), плеер (`just_audio`), Android-виджет (`home_widget`), tray/глобальные хоткеи на Windows (`tray_manager`, `hotkey_manager`).
- Windows-поддержка Flutter стабильнее, чем Android-поддержка MAUI; на Android Flutter заметно зрелее MAUI.

## Отклонённые варианты
- **MAUI**: слабый Android (полировка, cold start), rich-редактор — только WebView, мало готовых компонентов.
- **KMP + Compose Desktop**: лучший Android, но Windows-десктоп (tray, хоткеи, инсталлятор, размер JVM-дистрибутива) и отсутствие готового редактора удорожают.

## Последствия и риски
- Язык — Dart.
- Кириллица в пути проекта (`h:\.pet\Поток`) может ломать Gradle/CMake. Митигация: ASCII-junction (`mklink /J h:\.pet\potok`) и сборка через него, если проявится.
- Для Windows-сборки требуется VS 2022 Build Tools (C++ workload).
