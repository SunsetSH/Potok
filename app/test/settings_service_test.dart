import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/application/settings_service.dart';
import 'package:potok/infrastructure/db/database.dart';

void main() {
  test('theme mode and ASR progress preferences persist in app_meta', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = SettingsService(db: db);

    await settings.set(SettingsService.themeModeKey, 'system');
    await settings.set(SettingsService.systemLightThemeKey, 'paper');
    await settings.set(SettingsService.systemDarkThemeKey, 'studio-night');
    await settings.set(SettingsService.showTranscriptionProgressKey, '0');

    expect(await settings.get(SettingsService.themeModeKey), 'system');
    expect(await settings.get(SettingsService.systemLightThemeKey), 'paper');
    expect(
      await settings.get(SettingsService.systemDarkThemeKey),
      'studio-night',
    );
    expect(
      await settings.get(SettingsService.showTranscriptionProgressKey),
      '0',
    );
  });

  test('Windows shell flags default off and persist in app_meta', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = SettingsService(db: db);

    expect(await settings.get(SettingsService.trayCloseKey), isNull);
    expect(await settings.get(SettingsService.globalHotkeyKey), isNull);
    expect(await settings.get(SettingsService.androidWidgetProjectKey), isNull);
    expect(await settings.get(SettingsService.audioInputDeviceKey), isNull);

    await settings.set(SettingsService.trayCloseKey, '1');
    await settings.set(SettingsService.globalHotkeyKey, '1');
    await settings.set(SettingsService.androidWidgetProjectKey, 'project-1');
    await settings.set(SettingsService.audioInputDeviceKey, 'microphone-1');

    expect(await settings.get(SettingsService.trayCloseKey), '1');
    expect(await settings.get(SettingsService.globalHotkeyKey), '1');
    expect(
      await settings.get(SettingsService.androidWidgetProjectKey),
      'project-1',
    );
    expect(
      await settings.get(SettingsService.audioInputDeviceKey),
      'microphone-1',
    );
    final rows = await db.select(db.appMeta).get();
    expect(
      rows.map((row) => row.key),
      containsAll([
        SettingsService.trayCloseKey,
        SettingsService.globalHotkeyKey,
        SettingsService.androidWidgetProjectKey,
        SettingsService.audioInputDeviceKey,
      ]),
    );
  });
}
