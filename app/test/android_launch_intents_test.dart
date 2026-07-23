import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potok/presentation/app_shell.dart';
import 'package:potok/presentation/android_launch_intents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('launch request parser allowlists kinds and bounds shared text', () {
    expect(AndroidLaunchRequest.tryParse({'kind': 'unknown'}), isNull);
    expect(
      AndroidLaunchRequest.tryParse({'kind': 'share', 'text': '   '}),
      isNull,
    );

    final oversized = List.filled(
      AndroidLaunchRequest.maxTextCodePoints + 1,
      '💡',
    ).join();
    final parsed = AndroidLaunchRequest.tryParse({
      'kind': 'share',
      'text': oversized,
      'projectId': '../escape',
    });

    expect(parsed?.kind, AndroidLaunchKind.share);
    expect(parsed?.text?.runes.length, AndroidLaunchRequest.maxTextCodePoints);
    expect(parsed?.projectId, isNull);
  });

  test('integration serializes all pending native requests', () async {
    final port = _FakeLaunchPort([
      {'kind': 'text'},
      {'kind': 'audio'},
    ]);
    final firstPresented = Completer<void>();
    final releaseFirst = Completer<void>();
    final presented = <AndroidLaunchKind>[];
    final integration = AndroidLaunchIntentIntegration(
      port: port,
      present: (request) async {
        presented.add(request.kind);
        if (presented.length == 1) {
          firstPresented.complete();
          await releaseFirst.future;
        }
      },
    );

    final starting = integration.start();
    await firstPresented.future;
    expect(presented, [AndroidLaunchKind.text]);
    releaseFirst.complete();
    await starting;
    expect(presented, [AndroidLaunchKind.text, AndroidLaunchKind.audio]);

    port.add({'kind': 'share', 'text': 'shared'});
    await port.notifyAvailable();
    expect(presented.last, AndroidLaunchKind.share);
    integration.dispose();
  });

  test('mobile note detail gate does not stack a second route', () async {
    final gate = MobileNoteDetailRouteGate();
    final firstRoute = Completer<void>();
    var pushes = 0;

    gate.open(() {
      pushes += 1;
      return firstRoute.future;
    });
    gate.open(() async => pushes += 1);
    expect(pushes, 1);

    firstRoute.complete();
    await firstRoute.future;
    await Future<void>.delayed(Duration.zero);
    gate.open(() async => pushes += 1);
    expect(pushes, 2);
  });

  test('widget data uses the launch-intents native channel', () async {
    const channel = MethodChannel(
      MethodChannelAndroidLaunchIntentPort.channelName,
    );
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await MethodChannelAndroidLaunchIntentPort().updateWidgetData(
      notesJson: '[{"id":"n1"}]',
      projectsJson: '[]',
    );

    expect(received?.method, 'setWidgetData');
    expect(received?.arguments, {'notes': '[{"id":"n1"}]', 'projects': '[]'});
  });

  test('widget theme uses the launch-intents native channel', () async {
    const channel = MethodChannel(
      MethodChannelAndroidLaunchIntentPort.channelName,
    );
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await MethodChannelAndroidLaunchIntentPort().updateWidgetTheme(
      mode: 'system',
      fixedTheme: 'paper',
      lightTheme: 'studio',
      darkTheme: 'terminal',
    );

    expect(received?.method, 'setWidgetTheme');
    expect(received?.arguments, {
      'mode': 'system',
      'fixed': 'paper',
      'light': 'studio',
      'dark': 'terminal',
    });
  });
}

class _FakeLaunchPort implements AndroidLaunchIntentPort {
  final Queue<Object?> _pending;
  Future<void> Function()? _onAvailable;

  _FakeLaunchPort(Iterable<Object?> pending)
    : _pending = Queue<Object?>.of(pending);

  void add(Object? value) => _pending.addLast(value);

  Future<void> notifyAvailable() async => _onAvailable?.call();

  @override
  Future<void> updateWidgetProject({String? id, String? name}) async {}

  @override
  Future<void> updateWidgetData({
    required String notesJson,
    required String projectsJson,
  }) async {}

  @override
  Future<void> updateWidgetTheme({
    required String mode,
    required String fixedTheme,
    required String lightTheme,
    required String darkTheme,
  }) async {}

  @override
  void setOnAvailable(Future<void> Function()? callback) {
    _onAvailable = callback;
  }

  @override
  Future<Object?> takeNext() async =>
      _pending.isEmpty ? null : _pending.removeFirst();
}
