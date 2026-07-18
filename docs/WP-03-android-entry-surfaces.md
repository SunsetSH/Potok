# WP-03: Android entry surfaces (FR-NOT-001)

Статус: реализовано и автоматически проверено 2026-07-18; device smoke остаётся
в release matrix.

## Реализовано

- статические app shortcuts «Новая заметка» и «Записать аудио»;
- `ACTION_SEND text/plain`: текст от другого приложения открывает durable
  quick-capture draft с `SourceKind.share`;
- home-screen widget 2×1 показывает выбранный проект/«Без проекта» и
  даёт кнопки «Текст»/«Аудио» с target 48 dp;
- проект виджета выбирается в «Настройки → Виджет Android»; canonical ID
  хранится в `app_meta`, а native `SharedPreferences` — только cache ID/имени для
  `RemoteViews`;
- Android передаёт только allowlisted command через MethodChannel. Все сохранение,
  project validation, draft merge, permission flow и recorder lifecycle остаются в общем
  application/UI flow;
- входящий share ограничен 100 000 Unicode code points, неизвестные kind/ID
  отвергаются, а новый share не перезаписывает уже имеющийся draft;
- несколько launch requests сериализуются: следующий capture ждёт закрытия
  текущего.

## Проверки

- `flutter analyze` — 0 issues;
- `flutter test` — 147/147;
- `flutter build apk --release` — успешно, APK 141,5 MB;
- artifact manifest: minSdk 24, targetSdk 36; только microphone/notification/FGS
  permissions, `INTERNET` и `ACCESS_NETWORK_STATE` в release отсутствуют;
- app `lintVitalRelease` — no issues. Полный `lintRelease` блокируется линтом
  внутри `just_audio 0.10.6` (137 `NewApi` errors при его library minSdk 16), а не
  кодом приложения. Baseline, скрывающий этот долг, не добавлялся.

## Непроверенный device gate

В окружении нет подключённого Android-устройства или AVD. Перед production-релизом
нужно вручную проверить cold/warm launch каждого shortcut, share из двух приложений,
добавление/ресайз виджета, выбор/удаление project, permission denied/granted и TalkBack.
