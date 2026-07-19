import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'presentation/android_launch_intents.dart';
import 'presentation/app_shell.dart';
import 'presentation/app_shortcuts.dart';
import 'presentation/asr_first_run_prompt.dart';
import 'presentation/providers.dart';
import 'presentation/theme.dart';
import 'presentation/windows_integration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (windowsShellAvailable) {
    // Дёшево (нет обращений к диску); нужно для tray/hide до первого кадра.
    await windowManager.ensureInitialized();
  }
  // ADR-013: уведомление о фоновой докачке ASR-модели — единственная сеть в
  // приложении, показывается только пока идёт явно запущенное пользователем
  // скачивание.
  FileDownloader().configureNotification(
    running: const TaskNotification('Загрузка модели', '{filename} · {progress}'),
    complete: const TaskNotification('Модель загружена', '{filename}'),
    error: const TaskNotification('Ошибка загрузки модели', '{filename}'),
    paused: const TaskNotification('Загрузка приостановлена', '{filename}'),
    progressBar: true,
  );
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
    // Пока настройка не прочитана — Studio Light (дефолт ТЗ 0.6.6).
    final themeId = ref.watch(themeIdProvider).value ?? PotokThemeId.studio;
    return MaterialApp(
      title: 'Поток',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      theme: buildPotokTheme(themeId),
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('ru'), Locale('en')],
      builder: (context, child) =>
          AppShortcuts(child: child ?? const SizedBox.shrink()),
      home: const AsrFirstRunGate(child: AppShell()),
    );
  }
}
