import '../infrastructure/db/database.dart';

/// Локальные настройки приложения в app_meta (ключ → строка).
/// Не синхронизируются между устройствами (ТЗ 0.10.1).
class SettingsService {
  static const themeKey = 'theme';

  final AppDatabase db;

  SettingsService({required this.db});

  Future<String?> get(String key) async {
    final row = await (db.select(db.appMeta)..where((m) => m.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) {
    return db.into(db.appMeta).insertOnConflictUpdate(
          AppMetaCompanion.insert(key: key, value: value),
        );
  }

  Stream<String?> watch(String key) {
    return (db.select(db.appMeta)..where((m) => m.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }
}
