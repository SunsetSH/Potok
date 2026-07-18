import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../application/settings_service.dart';
import 'capture_sheet.dart';
import 'providers.dart';

/// Windows-shell интеграции (tray, глобальный hotkey) доступны только
/// в реальном рантайме: в flutter test плагинов нет.
bool get windowsShellAvailable =>
    !kIsWeb &&
    Platform.isWindows &&
    !Platform.environment.containsKey('FLUTTER_TEST');

enum GlobalHotkeyStatus {
  /// Настройка выключена или регистрация ещё не выполнялась.
  inactive,

  /// Ctrl+Alt+N зарегистрирован системно.
  active,

  /// Регистрация не удалась (сочетание занято другим приложением).
  conflict,
}

/// Опциональный tray lifecycle и глобальная горячая клавиша (ТЗ 37.8,
/// приложение A 41.2). Реагирует на настройки app_meta через SettingsService;
/// обе настройки по умолчанию выключены.
class WindowsShellIntegration with TrayListener, WindowListener {
  static const _menuOpen = 'open';
  static const _menuCapture = 'capture';
  static const _menuExit = 'exit';

  final SettingsService settings;

  /// Для сообщения в настройках при конфликте регистрации hotkey.
  final ValueNotifier<GlobalHotkeyStatus> hotkeyStatus = ValueNotifier(
    GlobalHotkeyStatus.inactive,
  );

  StreamSubscription<bool>? _traySubscription;
  StreamSubscription<bool>? _hotkeySubscription;
  bool _trayVisible = false;
  HotKey? _hotKey;
  bool _disposed = false;

  /// Side-эффекты плагинов сериализуются: быстрые переключения настроек
  /// не должны перегонять друг друга.
  Future<void> _serial = Future<void>.value();

  WindowsShellIntegration({required this.settings});

  Future<void> start() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    try {
      // Страховка от hotkey, пережившего hot restart.
      await hotKeyManager.unregisterAll();
    } catch (e) {
      debugPrint('hotkey cleanup failed: ${e.runtimeType}');
    }
    if (_disposed) return;
    _traySubscription = settings
        .watch(SettingsService.trayCloseKey)
        .map((value) => value == '1')
        .distinct()
        .listen((enabled) => _enqueue(() => _applyTray(enabled)));
    _hotkeySubscription = settings
        .watch(SettingsService.globalHotkeyKey)
        .map((value) => value == '1')
        .distinct()
        .listen((enabled) => _enqueue(() => _applyHotkey(enabled)));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _traySubscription?.cancel();
    await _hotkeySubscription?.cancel();
    windowManager.removeListener(this);
    trayManager.removeListener(this);

    // Let a plugin call that already started finish before destroying its
    // notifier and resources. Queued calls observe _disposed and become no-op.
    try {
      await _serial;
    } catch (_) {
      // _enqueue normally absorbs plugin errors; cleanup below still matters.
    }
    final hotKey = _hotKey;
    _hotKey = null;
    if (hotKey != null) {
      try {
        await hotKeyManager.unregister(hotKey);
      } catch (e) {
        debugPrint('hotkey unregister failed: ${e.runtimeType}');
      }
    }
    if (_trayVisible) {
      _trayVisible = false;
      try {
        await trayManager.destroy();
      } catch (e) {
        debugPrint('tray destroy failed: ${e.runtimeType}');
      }
    }
    hotkeyStatus.dispose();
  }

  void _enqueue(Future<void> Function() task) {
    _serial = _serial.then((_) async {
      if (_disposed) return;
      try {
        await task();
      } catch (e) {
        debugPrint('windows shell task failed: ${e.runtimeType}');
      }
    });
  }

  // ---------- Tray ----------

  Future<void> _applyTray(bool enabled) async {
    await windowManager.setPreventClose(enabled);
    if (enabled) {
      await trayManager.setIcon('assets/app_icon.ico');
      await trayManager.setToolTip('Поток');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: _menuOpen, label: 'Открыть «Поток»'),
            MenuItem(key: _menuCapture, label: 'Быстрая заметка'),
            MenuItem.separator(),
            MenuItem(key: _menuExit, label: 'Выход'),
          ],
        ),
      );
      _trayVisible = true;
    } else {
      _trayVisible = false;
      await trayManager.destroy();
    }
  }

  @override
  void onWindowClose() {
    _enqueue(() async {
      if (_trayVisible && await windowManager.isPreventClose()) {
        await windowManager.hide();
      }
    });
  }

  @override
  void onTrayIconMouseDown() {
    _enqueue(_showWindow);
  }

  @override
  void onTrayIconRightMouseDown() {
    _enqueue(trayManager.popUpContextMenu);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _menuOpen:
        _enqueue(_showWindow);
      case _menuCapture:
        _enqueue(() async {
          await _showWindow();
          _openQuickCapture();
        });
      case _menuExit:
        _enqueue(() async {
          _trayVisible = false;
          await trayManager.destroy();
          await windowManager.setPreventClose(false);
          await windowManager.destroy();
        });
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  void _openQuickCapture() {
    final context = appNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      unawaited(showCaptureSheet(context));
    }
  }

  // ---------- Глобальный hotkey ----------

  Future<void> _applyHotkey(bool enabled) async {
    final existing = _hotKey;
    _hotKey = null;
    if (existing != null) {
      try {
        await hotKeyManager.unregister(existing);
      } catch (e) {
        debugPrint('hotkey unregister failed: ${e.runtimeType}');
      }
    }
    if (!enabled) {
      hotkeyStatus.value = GlobalHotkeyStatus.inactive;
      return;
    }
    final hotKey = HotKey(
      key: LogicalKeyboardKey.keyN,
      modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );
    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) => _enqueue(() async {
          await _showWindow();
          _openQuickCapture();
        }),
      );
      _hotKey = hotKey;
      hotkeyStatus.value = GlobalHotkeyStatus.active;
    } catch (e) {
      // Конфликт (сочетание занято) — честно показываем в настройках,
      // приложение продолжает работать без глобального hotkey.
      debugPrint('global hotkey register failed: ${e.runtimeType}');
      hotkeyStatus.value = GlobalHotkeyStatus.conflict;
    }
  }
}

/// null вне Windows-рантайма (Android, тесты) — UI настроек скрывает секцию.
final windowsIntegrationProvider = Provider<WindowsShellIntegration?>((ref) {
  if (!windowsShellAvailable) return null;
  final integration = WindowsShellIntegration(
    settings: ref.watch(settingsServiceProvider),
  );
  unawaited(integration.start());
  ref.onDispose(() => unawaited(integration.dispose()));
  return integration;
});

final trayCloseEnabledProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(settingsServiceProvider)
      .watch(SettingsService.trayCloseKey)
      .map((value) => value == '1');
});

final globalHotkeyEnabledProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(settingsServiceProvider)
      .watch(SettingsService.globalHotkeyKey)
      .map((value) => value == '1');
});
