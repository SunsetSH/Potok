import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../application/drafts_service.dart';
import '../application/notes_service.dart';
import '../application/projects_service.dart';
import '../application/tags_service.dart';
import '../domain/clock.dart';
import '../domain/id_generator.dart';
import '../infrastructure/asr/sherpa_whisper_recognizer.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/db/device_identity.dart';
import '../infrastructure/media_store.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final mediaStoreProvider = FutureProvider<MediaStore>((ref) async {
  final support = await getApplicationSupportDirectory();
  final root = Directory(p.join(support.path, 'media'));
  await root.create(recursive: true);
  return MediaStore(root);
});

/// Dev-slice model location; the real model manager (packs, hashes,
/// activation) is WP-03. Override with POTOK_ASR_MODEL_DIR.
final asrModelDirProvider = Provider<String>((ref) {
  return Platform.environment['POTOK_ASR_MODEL_DIR'] ??
      r'C:\dev\models\sherpa-onnx-whisper-tiny';
});

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final idGeneratorProvider = Provider<IdGenerator>((ref) => const UuidV7Generator());

final deviceIdProvider = FutureProvider<String>((ref) {
  return DeviceIdentity.ensure(
      ref.watch(databaseProvider), ref.watch(idGeneratorProvider));
});

final notesServiceProvider = FutureProvider<NotesService>((ref) async {
  return NotesService(
    db: ref.watch(databaseProvider),
    media: await ref.watch(mediaStoreProvider.future),
    recognizer:
        SherpaWhisperRecognizer(modelDir: ref.watch(asrModelDirProvider)),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    deviceId: await ref.watch(deviceIdProvider.future),
  );
});

final projectsServiceProvider = FutureProvider<ProjectsService>((ref) async {
  return ProjectsService(
    db: ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    deviceId: await ref.watch(deviceIdProvider.future),
  );
});

/// Сидирует предустановленные глобальные теги при первом запуске.
final tagsServiceProvider = FutureProvider<TagsService>((ref) async {
  final service = TagsService(
    db: ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    deviceId: await ref.watch(deviceIdProvider.future),
  );
  await service.seedPresetsIfEmpty();
  return service;
});

final draftsServiceProvider = Provider<DraftsService>((ref) {
  return DraftsService(
    db: ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
  );
});
