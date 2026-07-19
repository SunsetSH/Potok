import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:potok/infrastructure/audio_recorder.dart';
import 'package:record/record.dart';

void main() {
  test('PCM stream is wrapped in a valid mono 16 kHz WAV header', () {
    final header = buildPcm16WavHeader(dataBytes: 32000);
    final data = ByteData.sublistView(header);

    expect(ascii.decode(header.sublist(0, 4)), 'RIFF');
    expect(data.getUint32(4, Endian.little), 32036);
    expect(ascii.decode(header.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(20, Endian.little), 1);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint16(34, Endian.little), 16);
    expect(ascii.decode(header.sublist(36, 40)), 'data');
    expect(data.getUint32(40, Endian.little), 32000);
  });

  test('PCM RMS level reacts to silence and signal', () {
    final silence = Uint8List(16);
    final signal = ByteData(16);
    for (var offset = 0; offset < signal.lengthInBytes; offset += 2) {
      signal.setInt16(offset, offset.isEven ? 12000 : -12000, Endian.little);
    }

    expect(pcm16RmsLevel(silence), 0);
    expect(pcm16RmsLevel(signal.buffer.asUint8List()), greaterThan(0.7));
  });

  group('RecordAudioRecorderAdapter wav pipeline', () {
    late Directory tempDir;
    late String wavPath;
    late _FakePlatformRecorder platform;
    late _InstrumentedFile file;
    late RecordAudioRecorderAdapter adapter;

    Uint8List chunk([int size = 320]) => Uint8List(size);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('potok_recorder_test');
      wavPath = p.join(tempDir.path, 'rec.wav.partial');
      platform = _FakePlatformRecorder();
      adapter = RecordAudioRecorderAdapter(
        recorder: platform,
        wavFileOpener: (path) async {
          file = _InstrumentedFile(await File(path).open(mode: FileMode.write));
          return file;
        },
      );
    });

    tearDown(() async {
      platform.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Future<void> startWav() => adapter.start(
      wavPath,
      format: AudioRecordingFormat.wavPcm16,
      bitRate: 0,
    );

    test(
      'disk write failure surfaces from stop() instead of a broken wav',
      () async {
        await startWav();
        platform.emit(chunk());
        await pumpEventQueue();

        file.failWrites = true;
        platform.emit(chunk());
        platform.emit(chunk());
        await pumpEventQueue();

        await expectLater(
          adapter.stop(),
          throwsA(isA<AudioRecorderWriteException>()),
        );
        expect(file.closed, isTrue);
        expect(
          File(wavPath).existsSync(),
          isFalse,
          reason: 'битый файл удалён',
        );

        // Состояние сброшено: адаптер снова готов к записи.
        await startWav();
        platform.emit(chunk());
        await pumpEventQueue();
        expect(await adapter.stop(), wavPath);
      },
    );

    test(
      'dispose() waits for the pending write queue before closing',
      () async {
        await startWav();
        final gate = Completer<void>();
        file.writeGate = gate.future;
        platform.emit(chunk());
        await pumpEventQueue();

        var disposed = false;
        final disposing = adapter.dispose().then((_) => disposed = true);
        await pumpEventQueue();
        expect(disposed, isFalse, reason: 'dispose ждёт очередь записи');
        expect(file.closed, isFalse);

        gate.complete();
        await disposing;
        expect(file.closed, isTrue);
        expect(file.closedAfterLastWrite, isTrue);
      },
    );

    test('stop() rolls back state when the platform stop throws', () async {
      await startWav();
      platform.emit(chunk());
      await pumpEventQueue();

      platform.stopError = PlatformException(code: 'record/stop-failed');
      await expectLater(adapter.stop(), throwsA(isA<PlatformException>()));
      expect(file.closed, isTrue, reason: 'файл закрыт несмотря на исключение');

      // wav-состояние откатилось: повторный stop() идёт по обычной ветке
      // платформенного рекордера, а не по несуществующей wav-записи.
      platform.stopError = null;
      expect(await adapter.stop(), isNull);
    });
  });
}

/// Фейк платформенного рекордера: отдаёт управляемый PCM-стрим.
class _FakePlatformRecorder extends Fake implements AudioRecorder {
  StreamController<Uint8List> _stream = StreamController<Uint8List>();
  PlatformException? stopError;

  void emit(Uint8List chunk) => _stream.add(chunk);

  void close() {
    if (!_stream.isClosed) _stream.close();
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    if (_stream.isClosed || _stream.hasListener) {
      _stream = StreamController<Uint8List>();
    }
    return _stream.stream;
  }

  @override
  Future<String?> stop() async {
    final error = stopError;
    if (error != null) throw error;
    close();
    return null;
  }

  @override
  Future<void> cancel() async => close();

  @override
  Future<void> dispose() async => close();
}

/// Обёртка над реальным файлом: контролируемые сбои и порядок операций.
class _InstrumentedFile extends Fake implements RandomAccessFile {
  final RandomAccessFile _inner;
  bool failWrites = false;
  Future<void>? writeGate;
  bool closed = false;
  bool _writePending = false;
  bool closedAfterLastWrite = false;

  _InstrumentedFile(this._inner);

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    _writePending = true;
    try {
      final gate = writeGate;
      if (gate != null) await gate;
      if (failWrites) throw const FileSystemException('disk full');
      await _inner.writeFrom(buffer, start, end);
      return this;
    } finally {
      _writePending = false;
    }
  }

  @override
  Future<RandomAccessFile> setPosition(int position) async {
    await _inner.setPosition(position);
    return this;
  }

  @override
  Future<RandomAccessFile> flush() async {
    await _inner.flush();
    return this;
  }

  @override
  Future<void> close() async {
    closed = true;
    closedAfterLastWrite = !_writePending;
    await _inner.close();
  }
}
