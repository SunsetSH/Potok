import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../application/drafts_service.dart';
import '../application/notes_service.dart';
import '../application/projects_service.dart';
import '../application/settings_service.dart';
import '../application/tags_service.dart';
import '../domain/clock.dart';
import '../domain/id_generator.dart';
import '../infrastructure/asr/sherpa_whisper_recognizer.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/db/device_identity.dart';
import '../infrastructure/media_store.dart';
import 'theme.dart';

// ---------- DI ----------

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

final idGeneratorProvider =
    Provider<IdGenerator>((ref) => const UuidV7Generator());

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

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService(db: ref.watch(databaseProvider));
});

// ---------- Тема ----------

final themeIdProvider = StreamProvider<PotokThemeId>((ref) {
  return ref
      .watch(settingsServiceProvider)
      .watch(SettingsService.themeKey)
      .map(PotokThemeId.fromStorage);
});

// ---------- Глобальные объекты UI ----------

/// Root navigator: глобальные шорткаты (Ctrl+N) открывают quick capture
/// без привязки к конкретному экрану.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Фокус строки поиска (Ctrl+K).
final searchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'notes-search');
  ref.onDispose(node.dispose);
  return node;
});

// ---------- Навигация sidebar ----------

sealed class NavSection {
  const NavSection();
}

class AllNotesSection extends NavSection {
  const AllNotesSection();
}

class NoProjectSection extends NavSection {
  const NoProjectSection();
}

class FavoritesSection extends NavSection {
  const FavoritesSection();
}

class TrashSection extends NavSection {
  const TrashSection();
}

class ProjectSection extends NavSection {
  final String projectId;
  const ProjectSection(this.projectId);

  @override
  bool operator ==(Object other) =>
      other is ProjectSection && other.projectId == projectId;

  @override
  int get hashCode => Object.hash(ProjectSection, projectId);
}

class NavSectionNotifier extends Notifier<NavSection> {
  @override
  NavSection build() => const AllNotesSection();

  void select(NavSection section) {
    if (state == section) return;
    state = section;
    // Раздел сменился — прежний выбор заметки не относится к новому списку.
    ref.read(selectedNoteIdProvider.notifier).select(null);
  }
}

final navSectionProvider =
    NotifierProvider<NavSectionNotifier, NavSection>(NavSectionNotifier.new);

class SelectedNoteIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedNoteIdProvider =
    NotifierProvider<SelectedNoteIdNotifier, String?>(
        SelectedNoteIdNotifier.new);

// ---------- Поиск и фильтр-чипы ----------

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

enum NoteChipFilter {
  all('Все'),
  inWork('В работе'),
  done('Выполнено'),
  withAudio('С аудио');

  final String label;
  const NoteChipFilter(this.label);
}

class ChipFilterNotifier extends Notifier<NoteChipFilter> {
  @override
  NoteChipFilter build() => NoteChipFilter.all;

  void select(NoteChipFilter filter) => state = filter;
}

final chipFilterProvider = NotifierProvider<ChipFilterNotifier, NoteChipFilter>(
    ChipFilterNotifier.new);

// ---------- Потоки данных ----------

final projectsProvider = StreamProvider<List<Project>>((ref) async* {
  final service = await ref.watch(projectsServiceProvider.future);
  yield* service.watchProjects();
});

/// Все живые заметки: счётчики sidebar и выбранная заметка detail-панели.
final allNotesProvider = StreamProvider<List<Note>>((ref) async* {
  final service = await ref.watch(notesServiceProvider.future);
  yield* service.watchNotes();
});

final trashNotesProvider = StreamProvider<List<Note>>((ref) async* {
  final service = await ref.watch(notesServiceProvider.future);
  yield* service.watchTrash();
});

/// Заметки текущего раздела sidebar.
final sectionNotesProvider = StreamProvider<List<Note>>((ref) async* {
  final section = ref.watch(navSectionProvider);
  final service = await ref.watch(notesServiceProvider.future);
  yield* switch (section) {
    AllNotesSection() => service.watchNotes(),
    NoProjectSection() => service.watchNotes(onlyNoProject: true),
    FavoritesSection() => service.watchNotes(onlyFavorites: true),
    ProjectSection(:final projectId) =>
      service.watchNotes(projectId: projectId),
    TrashSection() => service.watchTrash(),
  };
});

final searchResultsProvider = FutureProvider<List<Note>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const <Note>[];
  final service = await ref.watch(notesServiceProvider.future);
  return service.searchNotes(query);
});

/// Выбранная заметка — всегда свежая строка из общего потока (после
/// автосохранения revision меняется, и мутации должны видеть её).
final selectedNoteProvider = Provider<Note?>((ref) {
  final id = ref.watch(selectedNoteIdProvider);
  if (id == null) return null;
  final notes = ref.watch(allNotesProvider).value;
  if (notes == null) return null;
  for (final note in notes) {
    if (note.id == id) return note;
  }
  return null;
});

final noteTagsProvider =
    StreamProvider.family<List<Tag>, String>((ref, noteId) async* {
  final service = await ref.watch(tagsServiceProvider.future);
  yield* service.watchNoteTags(noteId);
});

/// Теги, доступные заметке: глобальные + теги её проекта.
final availableTagsProvider =
    StreamProvider.family<List<Tag>, String?>((ref, projectId) async* {
  final service = await ref.watch(tagsServiceProvider.future);
  yield* service.watchTags(projectId: projectId);
});

final readyAudioAssetProvider =
    StreamProvider.family<MediaAsset?, String>((ref, noteId) async* {
  final service = await ref.watch(notesServiceProvider.future);
  yield* service.watchReadyAudioAsset(noteId);
});

final revisionsProvider = StreamProvider.family<List<TranscriptRevision>,
    String>((ref, noteId) async* {
  final service = await ref.watch(notesServiceProvider.future);
  yield* service.watchRevisions(noteId);
});
