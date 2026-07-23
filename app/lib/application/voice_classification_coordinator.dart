import '../infrastructure/db/database.dart';
import 'notes_service.dart';
import 'projects_service.dart';
import 'settings_service.dart';
import 'tags_service.dart';
import 'voice_classifier.dart';

/// Result of processing one completed local transcript.
enum VoiceClassificationDisposition { confirmationRequired, applied }

class VoiceClassificationSuggestion {
  final String noteId;
  final List<Tag> tags;
  final Project? project;

  const VoiceClassificationSuggestion({
    required this.noteId,
    required this.tags,
    this.project,
  });

  bool get isEmpty => tags.isEmpty && project == null;
}

class VoiceClassificationResult {
  final VoiceClassificationDisposition disposition;
  final VoiceClassificationSuggestion suggestion;

  const VoiceClassificationResult({
    required this.disposition,
    required this.suggestion,
  });
}

/// Connects the persisted mode to completed ASR jobs.
///
/// Parsing and matching are local and deterministic. Only existing projects
/// and tags can be selected; transcript text is never persisted by this
/// coordinator or sent anywhere.
class VoiceClassificationCoordinator {
  final SettingsService settings;
  final NotesService notes;
  final ProjectsService projects;
  final TagsService tags;
  final VoiceClassifier classifier;
  final Set<String> _emittedSuggestionKeys = <String>{};

  VoiceClassificationCoordinator({
    required this.settings,
    required this.notes,
    required this.projects,
    required this.tags,
    this.classifier = const VoiceClassifier(),
  });

  Future<VoiceClassificationResult?> processTranscript(
    String noteId,
    String rawText,
  ) async {
    final mode = VoiceClassificationMode.fromStorage(
      await settings.get(SettingsService.voiceClassificationModeKey),
    );
    if (mode == VoiceClassificationMode.off) return null;

    final suggestion = await resolve(noteId, rawText);
    if (suggestion == null || suggestion.isEmpty) return null;
    final suggestionKey = _suggestionKey(suggestion);
    if (_emittedSuggestionKeys.contains(suggestionKey)) return null;

    if (mode == VoiceClassificationMode.auto) {
      await apply(suggestion);
      _emittedSuggestionKeys.add(suggestionKey);
      return VoiceClassificationResult(
        disposition: VoiceClassificationDisposition.applied,
        suggestion: suggestion,
      );
    }
    _emittedSuggestionKeys.add(suggestionKey);
    return VoiceClassificationResult(
      disposition: VoiceClassificationDisposition.confirmationRequired,
      suggestion: suggestion,
    );
  }

  Future<VoiceClassificationSuggestion?> resolve(
    String noteId,
    String rawText,
  ) async {
    final parsed = classifier.parse(rawText);
    if (parsed.isEmpty) return null;

    final note = await notes.getNote(noteId);
    if (note == null || note.deletedAtUtc != null) return null;

    final availableProjects = await projects.watchProjects().first;
    final matchedProject = classifier.matchProject(
      parsed.projectCandidates,
      availableProjects,
      (project) => project.name,
    );
    final effectiveProjectId = matchedProject?.id ?? note.projectId;
    final availableTags = await tags
        .watchTags(projectId: effectiveProjectId)
        .first;
    final matchedTags = classifier.matchTags(
      parsed.tagPhrases,
      availableTags,
      (tag) => tag.name,
    );
    final assignedTagIds = (await tags.watchNoteTags(noteId).first)
        .map((tag) => tag.id)
        .toSet();
    final tagsToApply = matchedTags
        .where((tag) => !assignedTagIds.contains(tag.id))
        .toList(growable: false);
    final projectToApply =
        matchedProject != null && matchedProject.id != note.projectId
        ? matchedProject
        : null;

    if (tagsToApply.isEmpty && projectToApply == null) return null;
    return VoiceClassificationSuggestion(
      noteId: noteId,
      tags: List.unmodifiable(tagsToApply),
      project: projectToApply,
    );
  }

  Future<void> apply(VoiceClassificationSuggestion suggestion) async {
    if (suggestion.project != null) {
      final fresh = await notes.getNote(suggestion.noteId);
      if (fresh == null || fresh.deletedAtUtc != null) return;
      await notes.moveToProject(fresh, suggestion.project!.id);
    }
    for (final tag in suggestion.tags) {
      await tags.assignTag(suggestion.noteId, tag.id);
    }
  }

  static String _suggestionKey(VoiceClassificationSuggestion suggestion) {
    final tagIds = suggestion.tags.map((tag) => tag.id).toList()..sort();
    return '${suggestion.noteId}|${suggestion.project?.id ?? ''}|${tagIds.join(',')}';
  }
}
