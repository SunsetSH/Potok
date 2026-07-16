import '../../domain/id_generator.dart';
import 'database.dart';

/// device_id создаётся при первом запуске и живёт в app_meta (ADR-008).
class DeviceIdentity {
  static const _key = 'device_id';

  static Future<String> ensure(AppDatabase db, IdGenerator ids) async {
    return db.transaction(() async {
      final existing = await (db.select(db.appMeta)
            ..where((m) => m.key.equals(_key)))
          .getSingleOrNull();
      if (existing != null) return existing.value;
      final id = ids.newId();
      await db.into(db.appMeta).insert(AppMetaCompanion.insert(
            key: _key,
            value: id,
          ));
      return id;
    });
  }
}
