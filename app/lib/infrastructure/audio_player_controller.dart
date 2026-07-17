import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlaybackState {
  final bool loading;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double speed;
  final String? error;

  const AudioPlaybackState({
    this.loading = true,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1,
    this.error,
  });

  AudioPlaybackState copyWith({
    bool? loading,
    bool? playing,
    Duration? position,
    Duration? duration,
    double? speed,
    String? error,
  }) => AudioPlaybackState(
    loading: loading ?? this.loading,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    speed: speed ?? this.speed,
    error: error,
  );
}

abstract class AudioPlaybackController extends ChangeNotifier {
  AudioPlaybackState get state;
  Future<void> open(String path);
  Future<void> toggle();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> skip(Duration delta);
  Future<void> setSpeed(double speed);
}

class JustAudioPlaybackController extends AudioPlaybackController {
  static const supportedSpeeds = <double>[0.75, 1, 1.25, 1.5, 2];

  final AudioPlayer _player;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  AudioPlaybackState _state = const AudioPlaybackState();
  bool _disposed = false;

  JustAudioPlaybackController({AudioPlayer? player})
    : _player = player ?? AudioPlayer(handleInterruptions: false);

  @override
  AudioPlaybackState get state => _state;

  @override
  Future<void> open(String path) async {
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.speech());
      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) => _pauseForInterruption()),
      );
      _subscriptions.add(
        session.interruptionEventStream.listen((event) {
          if (event.begin && event.type != AudioInterruptionType.duck) {
            _pauseForInterruption();
          }
        }),
      );
      _subscriptions.add(
        _player.playerStateStream.listen((value) {
          _update(
            playing: value.playing,
            loading:
                value.processingState == ProcessingState.loading ||
                value.processingState == ProcessingState.buffering,
          );
          if (value.processingState == ProcessingState.completed) {
            unawaited(_player.seek(Duration.zero));
            unawaited(_player.pause());
          }
        }),
      );
      _subscriptions.add(
        _player.positionStream.listen((value) => _update(position: value)),
      );
      _subscriptions.add(
        _player.durationStream.listen((value) {
          if (value != null) _update(duration: value);
        }),
      );
      final duration = await _player.setFilePath(path);
      _update(loading: false, duration: duration ?? Duration.zero);
    } catch (error) {
      _update(loading: false, error: 'audio_unavailable');
      rethrow;
    }
  }

  @override
  Future<void> toggle() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      final session = await AudioSession.instance;
      if (await session.setActive(true)) await _player.play();
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) async {
    final bounded = position < Duration.zero
        ? Duration.zero
        : position > _state.duration
        ? _state.duration
        : position;
    await _player.seek(bounded);
  }

  @override
  Future<void> skip(Duration delta) => seek(_state.position + delta);

  @override
  Future<void> setSpeed(double speed) async {
    if (!supportedSpeeds.contains(speed)) {
      throw ArgumentError.value(speed, 'speed', 'unsupported playback speed');
    }
    await _player.setSpeed(speed);
    _update(speed: speed);
  }

  Future<void> _pauseForInterruption() async {
    if (_player.playing) await _player.pause();
  }

  void _update({
    bool? loading,
    bool? playing,
    Duration? position,
    Duration? duration,
    double? speed,
    String? error,
  }) {
    if (_disposed) return;
    _state = _state.copyWith(
      loading: loading,
      playing: playing,
      position: position,
      duration: duration,
      speed: speed,
      error: error,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }
}
