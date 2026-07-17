import '../infrastructure/db/database.dart';
import '../infrastructure/media_store.dart';
import '../infrastructure/recording_platform.dart';

class StorageUsageService {
  final AppDatabase db;
  final MediaStore media;
  final RecordingPlatformPort platform;

  const StorageUsageService({
    required this.db,
    required this.media,
    required this.platform,
  });

  Future<StorageUsage> snapshot() async {
    final row = await db.customSelect('''
      SELECT
        COALESCE(SUM(CASE
          WHEN a.kind = 'audio' AND a.lifecycle_state = 'ready'
          THEN a.size_bytes ELSE 0 END), 0) AS audio_bytes,
        COALESCE(SUM(CASE
          WHEN a.kind = 'image' AND a.lifecycle_state = 'ready'
          THEN a.size_bytes ELSE 0 END), 0) AS image_bytes,
        COALESCE(SUM(CASE
          WHEN a.lifecycle_state = 'ready'
            AND (n.deleted_at_utc IS NOT NULL OR a.deleted_at_utc IS NOT NULL)
          THEN a.size_bytes ELSE 0 END), 0) AS trash_bytes,
        COALESCE(SUM(CASE
          WHEN a.lifecycle_state = 'missing' THEN 1 ELSE 0 END), 0)
          AS missing_count
      FROM media_assets a
      JOIN notes n ON n.id = a.owner_note_id
    ''').getSingle();
    int? freeBytes;
    try {
      freeBytes = await platform.freeBytes(media.root.path);
    } on Object {
      freeBytes = null;
    }
    return StorageUsage(
      audioBytes: row.read<int>('audio_bytes'),
      imageBytes: row.read<int>('image_bytes'),
      trashBytes: row.read<int>('trash_bytes'),
      missingCount: row.read<int>('missing_count'),
      freeBytes: freeBytes,
    );
  }
}

class StorageUsage {
  final int audioBytes;
  final int imageBytes;
  final int trashBytes;
  final int missingCount;
  final int? freeBytes;

  const StorageUsage({
    required this.audioBytes,
    required this.imageBytes,
    required this.trashBytes,
    required this.missingCount,
    required this.freeBytes,
  });

  int get managedBytes => audioBytes + imageBytes;
}
