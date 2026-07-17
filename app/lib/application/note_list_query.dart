import '../domain/types.dart';
import '../infrastructure/db/database.dart';

const _unchanged = Object();

/// Allowlisted list ordering. No column name ever comes from user input.
enum NoteSortField {
  createdAt('Создано'),
  updatedAt('Изменено'),
  eventAt('Событие'),
  title('Заголовок'),
  project('Проект');

  final String label;
  const NoteSortField(this.label);
}

enum NoteSortDirection { ascending, descending }

enum TagMatchMode { any, all }

class NoteListOrder {
  final NoteSortField field;
  final NoteSortDirection direction;

  const NoteListOrder({
    this.field = NoteSortField.createdAt,
    this.direction = NoteSortDirection.descending,
  });

  NoteListOrder copyWith({
    NoteSortField? field,
    NoteSortDirection? direction,
  }) => NoteListOrder(
    field: field ?? this.field,
    direction: direction ?? this.direction,
  );
}

/// Opaque keyset cursor. [sortValue] is interpreted only together with the
/// allowlisted [NoteListOrder] that produced it; [id] is the stable tie-breaker.
class NoteListCursor {
  final Object? sortValue;
  final String id;

  const NoteListCursor({required this.sortValue, required this.id});
}

class NoteListPage {
  final List<Note> notes;
  final NoteListCursor? nextCursor;
  final bool hasMore;

  const NoteListPage({
    required this.notes,
    required this.nextCursor,
    required this.hasMore,
  });
}

/// Counts used by navigation. Keeping them separate from list rows prevents
/// the sidebar from materializing every note when the journal grows large.
class NavigationSummary {
  final int total;
  final int noProject;
  final int favorites;
  final int trash;

  const NavigationSummary({
    required this.total,
    required this.noProject,
    required this.favorites,
    required this.trash,
  });

  static const empty = NavigationSummary(
    total: 0,
    noProject: 0,
    favorites: 0,
    trash: 0,
  );
}

/// Combined SQL-side filters for FR-SRC-005/006.
///
/// An empty set means "do not constrain by this dimension". Period bounds
/// are UTC epoch milliseconds, inclusive at the start and exclusive at the
/// end so adjacent calendar periods cannot overlap.
class NoteListFilter {
  final Set<String> projectIds;
  final bool includeNoProject;
  final Set<String> tagIds;
  final TagMatchMode tagMatchMode;
  final Set<NoteStatus> statuses;
  final int? periodStartUtc;
  final int? periodEndUtcExclusive;
  final bool favoriteOnly;
  final bool requireAudio;
  final bool requireImage;
  final bool requireTranscript;

  const NoteListFilter({
    this.projectIds = const {},
    this.includeNoProject = false,
    this.tagIds = const {},
    this.tagMatchMode = TagMatchMode.any,
    this.statuses = const {},
    this.periodStartUtc,
    this.periodEndUtcExclusive,
    this.favoriteOnly = false,
    this.requireAudio = false,
    this.requireImage = false,
    this.requireTranscript = false,
  });

  bool get isActive =>
      projectIds.isNotEmpty ||
      includeNoProject ||
      tagIds.isNotEmpty ||
      statuses.isNotEmpty ||
      periodStartUtc != null ||
      periodEndUtcExclusive != null ||
      favoriteOnly ||
      requireAudio ||
      requireImage ||
      requireTranscript;

  int get activeDimensionCount =>
      (projectIds.isNotEmpty || includeNoProject ? 1 : 0) +
      (tagIds.isNotEmpty ? 1 : 0) +
      (statuses.isNotEmpty ? 1 : 0) +
      (periodStartUtc != null || periodEndUtcExclusive != null ? 1 : 0) +
      (favoriteOnly ? 1 : 0) +
      (requireAudio ? 1 : 0) +
      (requireImage ? 1 : 0) +
      (requireTranscript ? 1 : 0);

  NoteListFilter copyWith({
    Set<String>? projectIds,
    bool? includeNoProject,
    Set<String>? tagIds,
    TagMatchMode? tagMatchMode,
    Set<NoteStatus>? statuses,
    Object? periodStartUtc = _unchanged,
    Object? periodEndUtcExclusive = _unchanged,
    bool? favoriteOnly,
    bool? requireAudio,
    bool? requireImage,
    bool? requireTranscript,
  }) => NoteListFilter(
    projectIds: projectIds ?? this.projectIds,
    includeNoProject: includeNoProject ?? this.includeNoProject,
    tagIds: tagIds ?? this.tagIds,
    tagMatchMode: tagMatchMode ?? this.tagMatchMode,
    statuses: statuses ?? this.statuses,
    periodStartUtc: identical(periodStartUtc, _unchanged)
        ? this.periodStartUtc
        : periodStartUtc as int?,
    periodEndUtcExclusive: identical(periodEndUtcExclusive, _unchanged)
        ? this.periodEndUtcExclusive
        : periodEndUtcExclusive as int?,
    favoriteOnly: favoriteOnly ?? this.favoriteOnly,
    requireAudio: requireAudio ?? this.requireAudio,
    requireImage: requireImage ?? this.requireImage,
    requireTranscript: requireTranscript ?? this.requireTranscript,
  );
}
