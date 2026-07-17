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
  Future<int?> freeBytes(String managedPath) {
    return _channel.invokeMethod<int>('getFreeBytes', {'path': managedPath});
  }

  @override
  Future<void> setRecordingActive(bool active) {
    return _channel.invokeMethod<void>('setRecordingActive', {
      'active': active,
    });
  }
}
