import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/app_shell.dart';
import 'presentation/capture_sheet.dart';
import 'presentation/providers.dart';
import 'presentation/theme.dart';

void main() {
  runApp(const ProviderScope(child: PotokApp()));
}

class PotokApp extends ConsumerWidget {
  const PotokApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Пока настройка не прочитана — Studio Light (дефолт ТЗ 0.6.6).
    final themeId = ref.watch(themeIdProvider).value ?? PotokThemeId.studio;
    return MaterialApp(
      title: 'Поток',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: buildPotokTheme(themeId),
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('ru'), Locale('en')],
      builder: (context, child) =>
          _GlobalShortcuts(child: child ?? const SizedBox.shrink()),
      home: const AppShell(),
    );
  }
}

class _NewNoteIntent extends Intent {
  const _NewNoteIntent();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// Горячие клавиши приложения (Windows): Ctrl+N — quick capture,
/// Ctrl+K — фокус в поиск. Обёртка выше Navigator, работает на всех экранах.
class _GlobalShortcuts extends ConsumerWidget {
  final Widget child;

  const _GlobalShortcuts({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _NewNoteIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _FocusSearchIntent(),
      },
      child: Actions(
        actions: {
          _NewNoteIntent: CallbackAction<_NewNoteIntent>(
            onInvoke: (_) {
              final navigatorContext = appNavigatorKey.currentContext;
              if (navigatorContext != null) {
                showCaptureSheet(navigatorContext);
              }
              return null;
            },
          ),
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) {
              ref.read(searchFocusProvider).requestFocus();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
