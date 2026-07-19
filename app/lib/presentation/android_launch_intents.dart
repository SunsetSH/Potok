import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/settings_service.dart';
import '../domain/types.dart';
import 'capture_sheet.dart';
import 'providers.dart';

bool get androidLaunchIntentsAvailable =>
    !kIsWeb &&
    Platform.isAndroid &&
    !Platform.environment.containsKey('FLUTTER_TEST');

enum AndroidLaunchKind { text, audio, share }

/// Allowlisted command received from Android. Share text is untrusted input;
/// the bridge accepts only plain text and bounds it to the note contract.
class AndroidLaunchRequest {
  static const maxTextCodePoints = 100000;

  final AndroidLaunchKind kind;
  final String? text;
  final String? projectId;

  const AndroidLaunchRequest({required this.kind, this.text, this.projectId});

  static AndroidLaunchRequest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = switch (raw['kind']) {
      'text' => AndroidLaunchKind.text,
      'audio' => AndroidLaunchKind.audio,
      'share' => AndroidLaunchKind.share,
      _ => null,
    };
    if (kind == null) return null;

    final rawProjectId = raw['projectId'];
    final projectId =
        rawProjectId is String &&
            RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(rawProjectId)
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
