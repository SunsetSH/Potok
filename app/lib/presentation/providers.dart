import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../application/backup_service.dart';
import '../application/clipboard_image_reader.dart';
import '../application/drafts_service.dart';
import '../application/export_service.dart';
import '../application/images_service.dart';
import '../application/media_repair_service.dart';
import '../application/note_list_query.dart';
import '../application/notes_service.dart';
import '../application/projects_service.dart';
import '../application/restore_service.dart';
import '../application/settings_service.dart';
import '../application/smart_views_service.dart';
import '../application/storage_usage_service.dart';
import '../application/tags_service.dart';
import '../application/transcription_queue.dart';
import '../domain/clock.dart';
import '../domain/id_generator.dart';
import '../domain/types.dart';
import '../infrastructure/asr/model_manager.dart';
import '../infrastructure/asr/sherpa_recognizer_factory.dart';
import '../infrastructure/audio_player_controller.dart';
import '../infrastructure/audio_recorder.dart';
import '../infrastructure/db/database.dart';
import '../infrastructure/db/device_identity.dart';
import '../infrastructure/media_store.dart';
import '../infrastructure/recording_platform.dart';
import '../infrastructure/system_clipboard_image_reader.dart';
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

final audioPlaybackControllerFactoryProvider =
    Provider<AudioPlaybackController Function()>((ref) {
      return JustAudioPlaybackController.new;
    });

final audioRecorderFactoryProvider = Provider<AudioRecorderPort Function()>((
  ref,
) {
  return RecordAudioRecorderAdapter.new;
});

/// Capture devices are queried through a short-lived recorder so the settings
/// page never owns the recorder used by an active capture route.
final audioInputDevicesProvider = FutureProvider<List<AudioInputDevice>>((
  ref,
) async {
  final recorder = ref.watch(audioRecorderFactoryProvider)();
  try {
    return await recorder.listInputDevices();
  } finally {
    await recorder.dispose();
  }
});

final audioInputDeviceIdProvider = StreamProvider<String?>((ref) {
  return ref
      .watch(settingsServiceProvider)
      .watch(SettingsService.audioInputDeviceKey)
      .map((value) => value == null || value.isEmpty ? null : value);
});

final recordingPlatformProvider = Provider<RecordingPlatformPort>((ref) {
  return MethodChannelRecordingPlatform();
});

/// Менеджер model pack'ов (WP-03, ADR-002). Dev-fallback: env
/// POTOK_ASR_MODEL_DIR указывает на папку модели без манифеста.
final modelManagerProvider = FutureProvider<AsrModelManager>((ref) async {
  final support = await getApplicationSupportDirectory();
  final root = Directory(p.join(support.path, 'models'));
  await root.create(recursive: true);
  final manager = AsrModelManager(
    modelsRoot: root,
    settings: ref.watch(settingsServiceProvider),
    devFallbackDir: Platform.environment['POTOK_ASR_MODEL_DIR'],
  );
  return manager;
});

final activeAsrModelDirectoryProvider = FutureProvider<String?>((ref) async {
  final manager = await ref.watch(modelManagerProvider.future);
  return manager.activeModelDir();
});

final asrReadyRecordingProvider = FutureProvider<bool>((ref) async {
  return await ref.watch(activeAsrModelDirectoryProvider.future) != null;
});

/// Durable-очередь расшифровки; при создании возвращает в работу job'ы,
/// зависшие после краха процесса.
final transcriptionQueueProvider = FutureProvider<TranscriptionQueue>((
  ref,
) async {
  final queue = TranscriptionQueue(
    db: ref.watch(databaseProvider),
    media: await ref.watch(mediaStoreProvider.future),
    models: await ref.watch(modelManagerProvider.future),
    recognizerFactory: (modelDir) => createSherpaRecognizer(modelDir),
    engineId: 'sherpa-onnx',
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    onTranscriptReady: (noteId, text) async {
      final notes = await ref.read(notesServiceProvider.future);
      await notes.suggestTitleFromTranscript(noteId, text);
    },
  );
  await queue.recoverOnStartup();
  return queue;
});

/// FR-AUD-005: after a ready audio publish, enqueue local ASR only when the
/// user has an active model. The audio commit never depends on this follow-up.
final automaticTranscriptionEnqueueProvider =
    Provider<Future<void> Function(String noteId, String assetId)>((ref) {
      return (noteId, assetId) async {
        final activeModelId = await ref
            .read(settingsServiceProvider)
            .get(AsrModelManager.activeModelKey);
        if (activeModelId == null || activeModelId.isEmpty) return;
        final queue = await ref.read(transcriptionQueueProvider.future);
        await queue.enqueue(noteId, assetId);
      };
    });

/// Манифест активной модели для UI настроек (null — модель не установлена
/// или пак битый; dev-fallback без манифеста здесь не показывается).
final activeAsrModelProvider = StreamProvider<ModelManifest?>((ref) async* {
  final manager = await ref.watch(modelManagerProvider.future);
  yield* ref
      .watch(settingsServiceProvider)
      .watch(AsrModelManager.activeModelKey)
      .asyncMap(
        (id) => id == null
            ? Future<ModelManifest?>.value()
            : manager.installedManifest(id),
      );
});

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => const UuidV7Generator(),
);

final deviceIdProvider = FutureProvider<String>((ref) {
  return DeviceIdentity.ensure(
    ref.watch(databaseProvider),
    ref.watch(idGeneratorProvider),
  );
});

final notesServiceProvider = FutureProvider<NotesService>((ref) async {
  return NotesService(
    db: ref.watch(databaseProvider),
    media: await ref.watch(mediaStoreProvider.future),
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

final imagesServiceProvider = FutureProvider<ImagesService>((ref) async {
  return ImagesService(
    db: ref.watch(databaseProvider),
    media: await ref.watch(mediaStoreProvider.future),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  );
});

final smartViewsServiceProvider = FutureProvider<SmartViewsService>((
  ref,
) async {
  return SmartViewsService(
    db: ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    deviceId: await ref.watch(deviceIdProvider.future),
  );
});

final mediaRecoveryProvider = FutureProvider<MediaRepairReport>((ref) async {
  final service = MediaRepairService(
    db: ref.watch(databaseProvider),
    media: await ref.watch(mediaStoreProvider.future),
    notes: await ref.watch(notesServiceProvider.future),
    clock: ref.watch(clockProvider),
  );
  return service.reconcile();
});

/// Non-blocking startup repair for image tombstones/orphans. Seven days keeps
/// crash-created ready files recoverable before automatic cleanup.
final imageRecoveryProvider = FutureProvider<ImageReconcileReport>((ref) async {
  await ref.watch(mediaRecoveryProvider.future);
  final service = await ref.watch(imagesServiceProvider.future);
  return service.reconcileOrphanImages(gracePeriod: const Duration(days: 7));
});

/// Файл inline-изображения по asset id (embed `asset://<id>`); null —
/// asset не готов или файл пропал, UI рисует плейсхолдер.
final imageAssetFileProvider = FutureProvider.family<File?, String>((
  ref,
  assetId,
) async {
  final service = await ref.watch(imagesServiceProvider.future);
  return service.resolveReadyImageFile(assetId);
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

final audioBitRateProvider = StreamProvider<int>((ref) {
  return ref
      .watch(settingsServiceProvider)
      .watch(SettingsService.audioBitRateKey)
      .map((value) {
        final parsed = int.tryParse(value ?? '');
        return const {48000, 64000, 96000}.contains(parsed) ? parsed! : 64000;
      });
});

final audioMaxMinutesProvider = StreamProvider<int>((ref) {
  return ref
      .watch(settingsServiceProvider)
      .watch(SettingsService.audioMaxMinutesKey)
      .map((value) {
        final parsed = int.tryParse(value ?? '');
        return const {10, 30, 60, 120}.contains(parsed) ? parsed! : 30;
      });
});

final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>((
  ref,
) async {
  final service = StorageUsageService(
    db: ref.watch(databaseProvider),
    media: await ref.watch(mediaStoreProvider.future),
    platform: ref.watch(recordingPlatformProvider),
  );
  return service.snapshot();
});

// ---------- WP-06: backup/restore/export ----------

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  return BackupService(
    db: ref.watch(databaseProvider),
    media: await ref.watch(mediaStoreProvider.future),
    clock: ref.watch(clockProvider),
  );
});

final restoreServiceProvider = FutureProvider<RestoreService>((ref) async {
  final support = await getApplicationSupportDirectory();
  return RestoreService(
    supportDir: support,
    currentSchemaVersion: ref.watch(databaseProvider).schemaVersion,
  );
});

final exportServiceProvider = FutureProvider<ExportService>((ref) async {
  return ExportService(
    db: ref.watch(databaseProvider),
    notes: await ref.watch(notesServiceProvider.future),
  );
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

/// Root messenger: SnackBar из глобальных шорткатов (Delete → корзина)
/// без привязки к конкретному Scaffold.
final appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Фокус строки поиска (Ctrl+K).
final searchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'notes-search');
  ref.onDispose(node.dispose);
  return node;
});

final clipboardImageReaderProvider = Provider<ClipboardImageReader>((ref) {
  return SystemClipboardImageReader();
});

/// Durable flush документа detail-панели (Ctrl+S, FR-NOT-006).
/// Панель регистрирует свой flush-колбэк; глобальный шорткат вызывает его,
/// не зная о внутреннем состоянии панели.
class NoteFlushRegistry {
  Future<void> Function()? _flush;

  void register(Future<void> Function() flush) => _flush = flush;

  void unregister(Future<void> Function() flush) {
    // Tear-off одного метода равен (==), но не обязательно identical.
    if (_flush == flush) _flush = null;
  }

  Future<void> flushNow() => _flush?.call() ?? Future<void>.value();
}

final noteFlushRegistryProvider = Provider<NoteFlushRegistry>(
  (ref) => NoteFlushRegistry(),
);

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

class SmartViewSection extends NavSection {
  final String viewId;
  final String name;

  const SmartViewSection(this.viewId, this.name);

  @override
  bool operator ==(Object other) =>
      other is SmartViewSection && other.viewId == viewId;

  @override
  int get hashCode => Object.hash(SmartViewSection, viewId);
}

class NavSectionNotifier extends Notifier<NavSection> {
  @override
  NavSection build() => const AllNotesSection();

  void select(NavSection section) {
    if (state == section) return;
    state = section;
    // Раздел сменился — прежний выбор заметки не относится к новому списку.
    ref.read(selectedNoteIdProvider.notifier).select(null);
    ref.read(bulkSelectedNoteIdsProvider.notifier).clear();
  }
}

final navSectionProvider = NotifierProvider<NavSectionNotifier, NavSection>(
  NavSectionNotifier.new,
);

class SelectedNoteIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedNoteIdProvider =
    NotifierProvider<SelectedNoteIdNotifier, String?>(
      SelectedNoteIdNotifier.new,
    );

class BulkSelectedNoteIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String id) {
    state = state.contains(id)
        ? Set.unmodifiable(state.where((value) => value != id))
        : Set.unmodifiable({...state, id});
  }

  void clear() => state = const {};
}

final bulkSelectedNoteIdsProvider =
    NotifierProvider<BulkSelectedNoteIdsNotifier, Set<String>>(
      BulkSelectedNoteIdsNotifier.new,
    );

// ---------- Поиск и фильтр-чипы ----------

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

enum NoteChipFilter {
  all('Все'),
  inWork('В работе'),
  done('Выполнено'),
  withAudio('С аудио');

  final String label;
  const NoteChipFilter(this.label);
}

class NoteListViewSettings {
  final NoteListFilter filter;
  final NoteListOrder order;

  const NoteListViewSettings({
    this.filter = const NoteListFilter(),
    this.order = const NoteListOrder(),
  });
}

class NoteListViewSettingsNotifier extends Notifier<NoteListViewSettings> {
  @override
  NoteListViewSettings build() => const NoteListViewSettings();

  void selectQuick(NoteChipFilter quick) {
    final next = switch (quick) {
      NoteChipFilter.all => state.filter.copyWith(
        statuses: const {},
        requireAudio: false,
      ),
      NoteChipFilter.inWork => state.filter.copyWith(
        statuses: const {NoteStatus.inWork},
        requireAudio: false,
      ),
      NoteChipFilter.done => state.filter.copyWith(
        statuses: const {NoteStatus.done},
        requireAudio: false,
      ),
      NoteChipFilter.withAudio => state.filter.copyWith(
        statuses: const {},
        requireAudio: true,
      ),
    };
    state = NoteListViewSettings(filter: next, order: state.order);
  }

  void apply({required NoteListFilter filter, required NoteListOrder order}) {
    state = NoteListViewSettings(filter: filter, order: order);
  }

  void clearFilters() {
    state = NoteListViewSettings(order: state.order);
  }
}

final noteListViewSettingsProvider =
    NotifierProvider<NoteListViewSettingsNotifier, NoteListViewSettings>(
      NoteListViewSettingsNotifier.new,
    );

final activeQuickFilterProvider = Provider<NoteChipFilter?>((ref) {
  final filter = ref.watch(noteListViewSettingsProvider).filter;
  if (filter.requireAudio && filter.statuses.isEmpty) {
    return NoteChipFilter.withAudio;
  }
  if (!filter.requireAudio && filter.statuses.length == 1) {
    return filter.statuses.single == NoteStatus.inWork
        ? NoteChipFilter.inWork
        : NoteChipFilter.done;
  }
  if (!filter.requireAudio && filter.statuses.isEmpty) {
    return NoteChipFilter.all;
  }
  return null;
});

// ---------- Потоки данных ----------

final projectsProvider = StreamProvider<List<Project>>((ref) async* {
  final service = await ref.watch(projectsServiceProvider.future);
  yield* service.watchProjects();
});

/// Все живые заметки: счётчики sidebar и выбранная заметка detail-панели.
final navigationSummaryProvider = StreamProvider<NavigationSummary>((
  ref,
) async* {
  final service = await ref.watch(notesServiceProvider.future);
  yield* service.watchNavigationSummary();
});

final projectNoteCountsProvider = StreamProvider<Map<String, int>>((
  ref,
) async* {
  final service = await ref.watch(notesServiceProvider.future);
  yield* service.watchProjectCounts();
});

final notesChangeProvider = StreamProvider<int>((ref) async* {
  final service = await ref.watch(notesServiceProvider.future);
  yield* service.watchChanges();
});

final smartViewsProvider = StreamProvider<List<SmartView>>((ref) async* {
  final service = await ref.watch(smartViewsServiceProvider.future);
  yield* service.watchViews();
});

/// Заметки текущего раздела sidebar.
class PagedNotesState {
  final List<Note> notes;
  final NoteListCursor? nextCursor;
  final bool hasMore;
  final bool loadingMore;

  const PagedNotesState({
    required this.notes,
    required this.nextCursor,
    required this.hasMore,
    this.loadingMore = false,
  });

  PagedNotesState copyWith({
    List<Note>? notes,
    NoteListCursor? nextCursor,
    bool? hasMore,
    bool? loadingMore,
  }) => PagedNotesState(
    notes: notes ?? this.notes,
    nextCursor: nextCursor ?? this.nextCursor,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

class PagedSectionNotesNotifier extends AsyncNotifier<PagedNotesState> {
  static const pageSize = 50;

  @override
  Future<PagedNotesState> build() async {
    ref.watch(notesChangeProvider);
    final section = ref.watch(navSectionProvider);
    final settings = ref.watch(noteListViewSettingsProvider);
    final service = await ref.watch(notesServiceProvider.future);
    final page = await _fetch(service, section, settings, after: null);
    return _fromPage(page);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final cursor = current.nextCursor;
    if (cursor == null) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final service = await ref.read(notesServiceProvider.future);
      final page = await _fetch(
        service,
        ref.read(navSectionProvider),
        ref.read(noteListViewSettingsProvider),
        after: cursor,
      );
      final stillCurrent = state.value;
      if (stillCurrent == null || stillCurrent.nextCursor != cursor) return;
      state = AsyncData(
        PagedNotesState(
          notes: List.unmodifiable([...current.notes, ...page.notes]),
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  static PagedNotesState _fromPage(NoteListPage page) => PagedNotesState(
    notes: page.notes,
    nextCursor: page.nextCursor,
    hasMore: page.hasMore,
  );

  static Future<NoteListPage> _fetch(
    NotesService service,
    NavSection section,
    NoteListViewSettings settings, {
    required NoteListCursor? after,
  }) {
    return switch (section) {
      AllNotesSection() || SmartViewSection() => service.fetchNotesPage(
        filter: settings.filter,
        order: settings.order,
        after: after,
        pageSize: pageSize,
      ),
      NoProjectSection() => service.fetchNotesPage(
        onlyNoProject: true,
        filter: settings.filter,
        order: settings.order,
        after: after,
        pageSize: pageSize,
      ),
      FavoritesSection() => service.fetchNotesPage(
        onlyFavorites: true,
        filter: settings.filter,
        order: settings.order,
        after: after,
        pageSize: pageSize,
      ),
      ProjectSection(:final projectId) => service.fetchNotesPage(
        projectId: projectId,
        filter: settings.filter,
        order: settings.order,
        after: after,
        pageSize: pageSize,
      ),
      TrashSection() => service.fetchTrashPage(
        after: after,
        pageSize: pageSize,
      ),
    };
  }
}

final pagedSectionNotesProvider =
    AsyncNotifierProvider<PagedSectionNotesNotifier, PagedNotesState>(
      PagedSectionNotesNotifier.new,
    );

/// Override seam for focused widget tests without constructing persistence.
final visiblePagedNotesProvider = Provider<AsyncValue<PagedNotesState>>(
  (ref) => ref.watch(pagedSectionNotesProvider),
);

final searchResultsProvider = FutureProvider<List<Note>>((ref) async {
  ref.watch(notesChangeProvider);
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const <Note>[];
  final service = await ref.watch(notesServiceProvider.future);
  final hits = await service.searchNotes(query);
  final section = ref.watch(navSectionProvider);
  final settings = ref.watch(noteListViewSettingsProvider);
  final ids = hits.map((note) => note.id);
  return switch (section) {
    AllNotesSection() || SmartViewSection() => service.filterNotesByIds(
      ids,
      filter: settings.filter,
      order: settings.order,
    ),
    NoProjectSection() => service.filterNotesByIds(
      ids,
      onlyNoProject: true,
      filter: settings.filter,
      order: settings.order,
    ),
    FavoritesSection() => service.filterNotesByIds(
      ids,
      onlyFavorites: true,
      filter: settings.filter,
      order: settings.order,
    ),
    ProjectSection(:final projectId) => service.filterNotesByIds(
      ids,
      projectId: projectId,
      filter: settings.filter,
      order: settings.order,
    ),
    TrashSection() => const <Note>[],
  };
});

/// Выбранная заметка — всегда свежая строка из общего потока (после
/// автосохранения revision меняется, и мутации должны видеть её).
final selectedNoteStreamProvider = StreamProvider.family<Note?, String>((
  ref,
  id,
) async* {
  final service = await ref.watch(notesServiceProvider.future);
  yield* service.watchNote(id);
});

final selectedNoteProvider = Provider<Note?>((ref) {
  final id = ref.watch(selectedNoteIdProvider);
  if (id == null) return null;
  return ref.watch(selectedNoteStreamProvider(id)).value;
});

final noteTagsProvider = StreamProvider.family<List<Tag>, String>((
  ref,
  noteId,
) async* {
  final service = await ref.watch(tagsServiceProvider.future);
  yield* service.watchNoteTags(noteId);
});

/// Теги, доступные заметке: глобальные + теги её проекта.
final availableTagsProvider = StreamProvider.family<List<Tag>, String?>((
  ref,
  projectId,
) async* {
  final service = await ref.watch(tagsServiceProvider.future);
  yield* service.watchTags(projectId: projectId);
});

final allTagsProvider = StreamProvider<List<Tag>>((ref) async* {
  final service = await ref.watch(tagsServiceProvider.future);
  yield* service.watchAllTags();
});

final readyAudioAssetProvider = StreamProvider.family<MediaAsset?, String>((
  ref,
  noteId,
) async* {
  final service = await ref.watch(notesServiceProvider.future);
  yield* service.watchReadyAudioAsset(noteId);
});

final audioAssetsProvider = StreamProvider.family<List<MediaAsset>, String>((
  ref,
  noteId,
) async* {
  final service = await ref.watch(notesServiceProvider.future);
  yield* service.watchAudioAssets(noteId);
});

final trashedAudioProvider = StreamProvider<List<TrashedAudioItem>>((
  ref,
) async* {
  final service = await ref.watch(notesServiceProvider.future);
  yield* service.watchTrashedAudio();
});

final revisionsProvider =
    StreamProvider.family<List<TranscriptRevision>, String>((
      ref,
      noteId,
    ) async* {
      final service = await ref.watch(notesServiceProvider.future);
      yield* service.watchRevisions(noteId);
    });
