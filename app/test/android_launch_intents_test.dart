import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:potok/presentation/android_launch_intents.dart';

void main() {
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
  void setOnAvailable(Future<void> Function()? callback) {
    _onAvailable = callback;
  }

  @override
  Future<Object?> takeNext() async =>
      _pending.isEmpty ? null : _pending.removeFirst();
}
