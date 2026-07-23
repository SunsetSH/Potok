import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/settings_service.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import 'app_shell.dart';
import 'capture_sheet.dart';
import 'providers.dart';
import 'theme.dart';

bool get androidLaunchIntentsAvailable =>
    !kIsWeb &&
    Platform.isAndroid &&
    !Platform.environment.containsKey('FLUTTER_TEST');

enum AndroidLaunchKind { text, audio, share, openNote }

/// Allowlisted command received from Android. Share text is untrusted input;
/// the bridge accepts only plain text and bounds it to the note contract.
class AndroidLaunchRequest {
  static const maxTextCodePoints = 100000;

  final AndroidLaunchKind kind;
  final String? text;
  final String? projectId;
  final String? noteId;

  const AndroidLaunchRequest({
    required this.kind,
    this.text,
    this.projectId,
    this.noteId,
  });

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static AndroidLaunchRequest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = switch (raw['kind']) {
      'text' => AndroidLaunchKind.text,
      'audio' => AndroidLaunchKind.audio,
      'share' => AndroidLaunchKind.share,
      'openNote' => AndroidLaunchKind.openNote,
      _ => null,
    };
    if (kind == null) return null;

    if (kind == AndroidLaunchKind.openNote) {
      final rawNoteId = raw['noteId'];
      if (rawNoteId is! String || !_safeId.hasMatch(rawNoteId)) return null;
      return AndroidLaunchRequest(kind: kind, noteId: rawNoteId);
    }

    final rawProjectId = raw['projectId'];
    final projectId = rawProjectId is String && _safeId.hasMatch(rawProjectId)
        ? rawProjectId
        : null;
    if (kind != AndroidLaunchKind.share) {
      return AndroidLaunchRequest(kind: kind, projectId: projectId);
    }

    final rawText = raw['text'];
    if (rawText is! String || rawText.trim().isEmpty) return null;
    final text = rawText.runes.length <= maxTextCodePoints
        ? rawText
        : String.fromCharCodes(rawText.runes.take(maxTextCodePoints));
    return AndroidLaunchRequest(kind: kind, text: text, projectId: projectId);
  }
}

abstract interface class AndroidLaunchIntentPort {
  Future<Object?> takeNext();

  Future<void> updateWidgetProject({String? id, String? name});

  /// Пушит компактный срез (последние заметки + проекты) в SharedPreferences,
  /// откуда его читают виджеты. JSON строится на стороне Flutter; виджет сам
  /// БД не открывает.
  Future<void> updateWidgetData({
    required String notesJson,
    required String projectsJson,
  });

  Future<void> updateWidgetTheme({
    required String mode,
    required String fixedTheme,
    required String lightTheme,
    required String darkTheme,
  });

  void setOnAvailable(Future<void> Function()? callback);
}

class MethodChannelAndroidLaunchIntentPort implements AndroidLaunchIntentPort {
  static const channelName = 'dev.potok/launch_intents';

  final MethodChannel channel;
  Future<void> Function()? _onAvailable;

  MethodChannelAndroidLaunchIntentPort({
    this.channel = const MethodChannel(channelName),
  });

  @override
  Future<Object?> takeNext() => channel.invokeMethod<Object?>('takeNext');

  @override
  Future<void> updateWidgetProject({String? id, String? name}) =>
      channel.invokeMethod<void>('setWidgetProject', {'id': id, 'name': name});

  @override
  Future<void> updateWidgetData({
    required String notesJson,
    required String projectsJson,
  }) => channel.invokeMethod<void>('setWidgetData', {
    'notes': notesJson,
    'projects': projectsJson,
  });

  @override
  Future<void> updateWidgetTheme({
    required String mode,
    required String fixedTheme,
    required String lightTheme,
    required String darkTheme,
  }) => channel.invokeMethod<void>('setWidgetTheme', {
    'mode': mode,
    'fixed': fixedTheme,
    'light': lightTheme,
    'dark': darkTheme,
  });

  @override
  void setOnAvailable(Future<void> Function()? callback) {
    _onAvailable = callback;
    if (callback == null) {
      channel.setMethodCallHandler(null);
      return;
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'launchIntentAvailable') {
        await _onAvailable?.call();
      }
    });
  }
}

/// Serializes native entry requests. A second share/widget tap waits until the
/// current capture route closes instead of overwriting or dropping its draft.
class AndroidLaunchIntentIntegration {
  final AndroidLaunchIntentPort port;
  final Future<void> Function(AndroidLaunchRequest request) present;

  bool _disposed = false;
  bool _draining = false;
  bool _drainAgain = false;

  AndroidLaunchIntentIntegration({required this.port, required this.present});

  Future<void> start() async {
    port.setOnAvailable(_drain);
    await _drain();
  }

  Future<void> updateWidgetProject({String? id, String? name}) =>
      port.updateWidgetProject(id: id, name: name);

  Future<void> updateWidgetData({
    required String notesJson,
    required String projectsJson,
  }) => port.updateWidgetData(notesJson: notesJson, projectsJson: projectsJson);

  Future<void> updateWidgetTheme({
    required String mode,
    required String fixedTheme,
    required String lightTheme,
    required String darkTheme,
  }) => port.updateWidgetTheme(
    mode: mode,
    fixedTheme: fixedTheme,
    lightTheme: lightTheme,
    darkTheme: darkTheme,
  );

  Future<void> _drain() async {
    if (_disposed) return;
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        while (!_disposed) {
          final request = AndroidLaunchRequest.tryParse(await port.takeNext());
          if (request == null) break;
          await present(request);
        }
      } while (_drainAgain && !_disposed);
    } on PlatformException catch (error) {
      debugPrint('android launch bridge failed: ${error.runtimeType}');
    } catch (error) {
      debugPrint('android launch handling failed: ${error.runtimeType}');
    } finally {
      _draining = false;
    }
  }

  void dispose() {
    _disposed = true;
    port.setOnAvailable(null);
  }
}

final androidLaunchIntegrationProvider =
    Provider<AndroidLaunchIntentIntegration?>((ref) {
      if (!androidLaunchIntentsAvailable) return null;
      late final AndroidLaunchIntentIntegration integration;
      integration = AndroidLaunchIntentIntegration(
        port: MethodChannelAndroidLaunchIntentPort(),
        present: (request) async {
          if (request.kind == AndroidLaunchKind.openNote) {
            await _openNoteFromWidget(ref, request.noteId!);
            return;
          }
          await waitForCaptureSheetClosed();
          String? validProjectId;
          if (request.projectId != null) {
            try {
              final projects = await ref.read(projectsProvider.future);
              if (projects.any((project) => project.id == request.projectId)) {
                validProjectId = request.projectId;
              }
            } catch (_) {
              // Capture still opens safely with "No project".
            }
          }
          // Навигатор может ещё не построиться (холодный старт). Ждём с
          // лимитом, чтобы не залипнуть в _draining навсегда.
          const step = Duration(milliseconds: 16);
          const navigatorTimeout = Duration(seconds: 10);
          var waited = Duration.zero;
          while (appNavigatorKey.currentContext == null) {
            if (waited >= navigatorTimeout) {
              debugPrint('android launch intent dropped: navigator not ready');
              return;
            }
            await Future<void>.delayed(step);
            waited += step;
          }
          final context = appNavigatorKey.currentContext;
          if (context == null || !context.mounted) return;
          await showCaptureSheet(
            context,
            startWithAudio: request.kind == AndroidLaunchKind.audio,
            initialText: request.text,
            initialProjectId: validProjectId,
            sourceKind: request.kind == AndroidLaunchKind.share
                ? SourceKind.share
                : SourceKind.widget,
          );
        },
      );
      unawaited(integration.start());
      ref.onDispose(integration.dispose);
      return integration;
    });

/// Открывает заметку по deep-link из виджета: выбирает её в
/// [selectedNoteIdProvider] (detail-панель это читает), а на узком макете
/// поднимает поверх списка полноэкранную карточку. Ждёт готовности навигатора
/// на холодном старте (как и capture-поток).
Future<void> _openNoteFromWidget(Ref ref, String noteId) async {
  try {
    final service = await ref.read(notesServiceProvider.future);
    final note = await service.getNote(noteId);
    if (note == null || note.deletedAtUtc != null) return;
  } catch (_) {
    return; // заметка недоступна — молча выходим
  }
  ref.read(selectedNoteIdProvider.notifier).select(noteId);

  const step = Duration(milliseconds: 16);
  const navigatorTimeout = Duration(seconds: 10);
  var waited = Duration.zero;
  while (appNavigatorKey.currentContext == null) {
    if (waited >= navigatorTimeout) return;
    await Future<void>.delayed(step);
    waited += step;
  }
  final context = appNavigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  // Широкий макет показывает выбранную заметку в постоянной detail-панели —
  // отдельный маршрут нужен только на узком.
  if (MediaQuery.sizeOf(context).width < 900) {
    await Navigator.of(context).push(buildNoteDetailRoute());
  }
}

final androidWidgetProjectProvider = StreamProvider<String?>((ref) {
  return ref
      .watch(settingsServiceProvider)
      .watch(SettingsService.androidWidgetProjectKey)
      .map((value) => value == null || value.isEmpty ? null : value);
});

/// Mirrors the chosen project into Android's small RemoteViews cache. The
/// widget never opens SQLite itself; its ID is validated again before capture.
final androidWidgetSyncProvider = Provider<void>((ref) {
  if (!androidLaunchIntentsAvailable) return;
  final integration = ref.watch(androidLaunchIntegrationProvider);
  final selectedId = ref.watch(androidWidgetProjectProvider).value;
  final projects = ref.watch(projectsProvider).value;
  if (integration == null || projects == null) return;
  final selected = selectedId == null
      ? null
      : projects.where((project) => project.id == selectedId).firstOrNull;
  unawaited(
    integration
        .updateWidgetProject(id: selected?.id, name: selected?.name)
        .catchError((Object error) {
          debugPrint('android widget sync failed: ${error.runtimeType}');
        }),
  );
});

/// Keeps RemoteViews on the same fixed theme or system day/night pair as the
/// Flutter application. Native widgets resolve current uiMode themselves, so
/// they also update when Flutter is not running.
final androidWidgetThemeSyncProvider = Provider<void>((ref) {
  if (!androidLaunchIntentsAvailable) return;
  final integration = ref.watch(androidLaunchIntegrationProvider);
  if (integration == null) return;
  final mode = ref.watch(potokThemeModeProvider).value ?? PotokThemeMode.fixed;
  final fixed = ref.watch(themeIdProvider).value ?? PotokThemeId.studio;
  final light =
      ref.watch(systemLightThemeProvider).value ?? PotokThemeId.studio;
  final dark =
      ref.watch(systemDarkThemeProvider).value ?? PotokThemeId.studioNight;
  unawaited(
    integration
        .updateWidgetTheme(
          mode: mode.name,
          fixedTheme: fixed.storageKey,
          lightTheme: light.storageKey,
          darkTheme: dark.storageKey,
        )
        .catchError((Object error) {
          debugPrint('android widget theme sync failed: ${error.runtimeType}');
        }),
  );
});

final _widgetRecentNotesProvider = StreamProvider<List<Note>>((ref) async* {
  final service = await ref.watch(notesServiceProvider.future);
  // Enough rows for a useful native picker while keeping the private
  // SharedPreferences projection bounded. Dynamic selections remain stable
  // because they are re-evaluated from this newest-first snapshot.
  yield* service.watchRecentNotes(limit: 200);
});

String _widgetTitle(Note note) {
  final trimmed = note.title?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  final lines = note.documentPlainText
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  return lines.isEmpty ? 'Аудиозаметка' : lines.first;
}

String _widgetSnippet(Note note) {
  final lines = note.documentPlainText
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  final rest = lines.length > 1 ? lines.skip(1).join(' ') : '';
  return rest.length > 140 ? '${rest.substring(0, 140)}…' : rest;
}

/// Пушит компактный срез последних заметок и проектов в SharedPreferences,
/// откуда его читают виджеты (список, последняя, выбранная). Обновляется
/// при любом изменении заметок/проектов. Виджет БД не открывает.
final androidWidgetDataSyncProvider = Provider<void>((ref) {
  if (!androidLaunchIntentsAvailable) return;
  final integration = ref.watch(androidLaunchIntegrationProvider);
  final notes = ref.watch(_widgetRecentNotesProvider).value;
  final projects = ref.watch(projectsProvider).value;
  if (integration == null || notes == null || projects == null) return;

  final projectNames = {
    for (final project in projects) project.id: project.name,
  };
  final notesJson = jsonEncode([
    for (final note in notes)
      {
        'id': note.id,
        'title': _widgetTitle(note),
        'snippet': _widgetSnippet(note),
        'project': note.projectId == null
            ? ''
            : (projectNames[note.projectId] ?? ''),
        'projectId': note.projectId ?? '',
        'favorite': note.isFavorite,
        'status': note.status.db,
      },
  ]);
  final projectsJson = jsonEncode([
    for (final project in projects) {'id': project.id, 'name': project.name},
  ]);
  unawaited(
    integration
        .updateWidgetData(notesJson: notesJson, projectsJson: projectsJson)
        .catchError((Object error) {
          debugPrint('android widget data sync failed: ${error.runtimeType}');
        }),
  );
});
