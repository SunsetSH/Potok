import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class RecordingPlatformPort {
  Future<int?> freeBytes(String managedPath);

  /// Keeps the platform recording contract active: foreground service on
  /// Android and sleep inhibition on Windows.
  Future<void> setRecordingActive(bool active);
}

class MethodChannelRecordingPlatform implements RecordingPlatformPort {
  static const _channel = MethodChannel('dev.potok/recording');

  @override
  Future<int?> freeBytes(String managedPath) async {
    try {
      return await _channel.invokeMethod<int>('getFreeBytes', {
        'path': managedPath,
      });
    } on MissingPluginException {
      return null; // платформа без канала (тесты, новый target) — не критично
    } on PlatformException catch (error) {
      debugPrint('recording_platform.getFreeBytes failed: ${error.code}');
      return null;
    }
  }

  @override
  Future<void> setRecordingActive(bool active) async {
    try {
      await _channel.invokeMethod<void>('setRecordingActive', {
        'active': active,
      });
    } on MissingPluginException {
      // best-effort контракт: отсутствие канала не должно ронять запись
    } on PlatformException catch (error) {
      debugPrint('recording_platform.setRecordingActive failed: ${error.code}');
    }
  }
}
