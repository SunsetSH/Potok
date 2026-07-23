import '../infrastructure/db/database.dart';

/// Режим голосовой классификации: как поступать с распознанными в речи
/// командами «поставь тег…»/«в проект…» после принятия расшифровки.
enum VoiceClassificationMode {
  /// Не разбирать команды вовсе (значение по умолчанию — фича opt-in).
  off,

  /// Применять совпавшие теги/проект сразу, без вопросов.
  auto,

  /// Показать найденное и применить только после подтверждения.
  confirm;

  String get storageValue => name;

  static VoiceClassificationMode fromStorage(String? value) {
    return VoiceClassificationMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => VoiceClassificationMode.off,
    );
  }
}

/// Локальные настройки приложения в app_meta (ключ → строка).
/// Не синхронизируются между устройствами (ТЗ 0.10.1).
class SettingsService {
  static const themeKey = 'theme';
  static const themeModeKey = 'theme_mode';
  static const systemLightThemeKey = 'theme_system_light';
  static const systemDarkThemeKey = 'theme_system_dark';
  static const showTranscriptionProgressKey = 'show_transcription_progress';
  static const audioBitRateKey = 'audio_bit_rate';
  static const audioMaxMinutesKey = 'audio_max_minutes';

  /// Режим голосовой классификации (см. [VoiceClassificationMode]).
  static const voiceClassificationModeKey = 'voice_classification_mode';

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

  Future<void> remove(String key) {
    return (db.delete(db.appMeta)..where((m) => m.key.equals(key))).go();
  }

  Stream<String?> watch(String key) {
    return (db.select(db.appMeta)..where((m) => m.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }
}
