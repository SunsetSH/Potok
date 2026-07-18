import '../infrastructure/db/database.dart';

/// Локальные настройки приложения в app_meta (ключ → строка).
/// Не синхронизируются между устройствами (ТЗ 0.10.1).
class SettingsService {
  static const themeKey = 'theme';
  static const audioBitRateKey = 'audio_bit_rate';
  static const audioMaxMinutesKey = 'audio_max_minutes';

  /// Windows capture device ID reported by `record`; missing/empty means the
  /// current system default. The value is local to this installation.
  static const audioInputDeviceKey = 'audio_input_device_id';

  /// Windows: close сворачивает в трей вместо выхода ('1'/'0', по умолч. выкл).
  static const trayCloseKey = 'win_tray_on_close';

  /// Windows: глобальная горячая клавиша Ctrl+Alt+N ('1'/'0', по умолч. выкл).
  static const globalHotkeyKey = 'win_global_hotkey';

  /// Android widget: project preselected for new notes; empty/missing means
  /// "No project". Native widget cache stores the matching display name only.
  static const androidWidgetProjectKey = 'android_widget_project_id';

  final AppDatabase db;

  SettingsService({required this.db});

  Future<String?> get(String key) async {
    final row = await (db.select(
      db.appMeta,
    )..where((m) => m.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) {
    return db
        .into(db.appMeta)
        .insertOnConflictUpdate(
          AppMetaCompanion.insert(key: key, value: value),
        );
  }

  Stream<String?> watch(String key) {
    return (db.select(db.appMeta)..where((m) => m.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }
}
