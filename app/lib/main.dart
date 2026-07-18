import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'presentation/android_launch_intents.dart';
import 'presentation/app_shell.dart';
import 'presentation/app_shortcuts.dart';
import 'presentation/providers.dart';
import 'presentation/theme.dart';
import 'presentation/windows_integration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (windowsShellAvailable) {
    // Дёшево (нет обращений к диску); нужно для tray/hide до первого кадра.
    await windowManager.ensureInitialized();
  }
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
      home: const AppShell(),
    );
  }
}
