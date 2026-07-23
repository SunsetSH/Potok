import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'infrastructure/recording_platform.dart';
import 'presentation/android_launch_intents.dart';
import 'presentation/app_shell.dart';
import 'presentation/app_shortcuts.dart';
import 'presentation/asr_first_run_prompt.dart';
import 'presentation/providers.dart';
import 'presentation/theme.dart';
import 'presentation/voice_classification.dart';
import 'presentation/windows_integration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (windowsShellAvailable) {
    // Дёшево (нет обращений к диску); нужно для tray/hide до первого кадра.
    await windowManager.ensureInitialized();
  }
  // Свежий процесс — значит запись гарантированно не идёт (её состояние жило
  // только в памяти предыдущего процесса). Если предыдущий процесс убили
  // прямо во время записи, Dart-код очистки (dispose()) не успел выполниться,
  // и уведомление foreground-сервиса на Android могло остаться висеть.
  // Сбрасываем его безусловно при каждом старте — идемпотентно и не мешает,
  // даже если ничего убирать не нужно.
  unawaited(MethodChannelRecordingPlatform().setRecordingActive(false));
  // ADR-013: уведомление о фоновой докачке ASR-модели — единственная сеть в
  // приложении, показывается только пока идёт явно запущенное пользователем
  // скачивание.
  FileDownloader().configureNotification(
    running: const TaskNotification(
      'Загрузка модели',
      '{filename} · {progress}',
    ),
    complete: const TaskNotification('Модель загружена', '{filename}'),
    error: const TaskNotification('Ошибка загрузки модели', '{filename}'),
    paused: const TaskNotification('Загрузка приостановлена', '{filename}'),
    progressBar: true,
  );
  // Ключ к «не отменяется при сворачивании/скринлоке»: каждый файл model
  // pack, включая маленькие joiner/tokens, идёт в Android foreground-сервисе.
  // Иначе OS может отменить короткий следующий worker между большими файлами
  // сразу после screen lock, и весь уже почти скачанный pack будет отвергнут.
  // Foreground dataSync переживает Doze/блокировку экрана.
  // Требует running-уведомления (настроено выше), FOREGROUND_SERVICE_DATA_SYNC
  // и объявления SystemForegroundService в манифесте.
  await FileDownloader().configure(
    androidConfig: [
      (Config.runInForeground, Config.always),
      // Model files are hundreds of megabytes. The default `whenAble`
      // cache policy can select Android's quota-limited cache and then fail
      // (or lose resume data) half-way through a large transfer.
      (Config.useCacheDir, Config.never),
    ],
  );
  // В отличие от отдельных track/reschedule, `start` также забирает события,
  // накопленные нативным загрузчиком, пока Flutter-движок был приостановлен.
  // Иначе завершившийся при скринлоке transfer мог навсегда остаться awaited.
  await FileDownloader().start();
  runApp(const ProviderScope(child: PotokApp()));
}

class PotokApp extends ConsumerWidget {
  const PotokApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Активирует опциональные tray/hotkey интеграции (null вне Windows).
    ref.watch(windowsIntegrationProvider);
    ref.watch(androidLaunchIntegrationProvider);
    ref.watch(androidWidgetSyncProvider);
    ref.watch(androidWidgetDataSyncProvider);
    ref.watch(androidWidgetThemeSyncProvider);
    ref.watch(asrDownloadRecoveryProvider);
    // Пока настройка не прочитана — Studio Light (дефолт ТЗ 0.6.6).
    final themeId = ref.watch(themeIdProvider).value ?? PotokThemeId.studio;
    final themeMode =
        ref.watch(potokThemeModeProvider).value ?? PotokThemeMode.fixed;
    final systemLight =
        ref.watch(systemLightThemeProvider).value ?? PotokThemeId.studio;
    final systemDark =
        ref.watch(systemDarkThemeProvider).value ?? PotokThemeId.studioNight;
    return MaterialApp(
      title: 'Поток',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      darkTheme: themeMode == PotokThemeMode.system
          ? buildPotokTheme(systemDark)
          : buildPotokTheme(themeId),
      themeMode: themeMode == PotokThemeMode.system
          ? ThemeMode.system
          : ThemeMode.light,
      // In system mode MaterialApp selects these two complete Potok themes
      // from platformBrightness on both Android and Windows.
      theme: themeMode == PotokThemeMode.system
          ? buildPotokTheme(systemLight)
          : buildPotokTheme(themeId),
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('ru'), Locale('en')],
      builder: (context, child) =>
          AppShortcuts(child: child ?? const SizedBox.shrink()),
      home: const VoiceClassificationHost(
        child: AsrFirstRunGate(child: AppShell()),
      ),
    );
  }
}
