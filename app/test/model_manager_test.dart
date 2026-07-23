import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:potok/application/settings_service.dart';
import 'package:potok/infrastructure/asr/model_file_downloader.dart';
import 'package:potok/infrastructure/asr/model_manager.dart';
import 'package:potok/infrastructure/db/database.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late Directory modelsRoot;
  late Directory source;
  late SettingsService settings;
  late AsrModelManager manager;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('potok_models_test');
    modelsRoot = Directory(p.join(temp.path, 'models'))..createSync();
    source = Directory(p.join(temp.path, 'pack'))..createSync();
    settings = SettingsService(db: db);
    manager = AsrModelManager(modelsRoot: modelsRoot, settings: settings);
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  /// Пишет валидный пак в [source]: файлы + манифест с их настоящими
  /// SHA-256. [corruptHashOf] подменяет hash одного файла на неверный.
  Future<void> writePack({
    String modelId = 'whisper-tiny',
    Map<String, String> contents = const {
      'encoder.int8.onnx': 'encoder-bytes',
      'decoder.int8.onnx': 'decoder-bytes',
      'tokens.txt': 'token-bytes',
    },
    String? corruptHashOf,
    String? omitFile,
  }) async {
    final files = <String, String>{};
    for (final entry in contents.entries) {
      final bytes = utf8.encode(entry.value);
      if (entry.key != omitFile) {
        await File(p.join(source.path, entry.key)).writeAsBytes(bytes);
      }
      files[entry.key] = entry.key == corruptHashOf
          ? '0' * 64
          : sha256.convert(bytes).toString();
    }
    await File(
      p.join(source.path, AsrModelManager.manifestFileName),
    ).writeAsString(
      json.encode({
        'model_id': modelId,
        'engine': 'sherpa-onnx',
        'model_type': 'whisper',
        'languages': ['ru', 'en'],
        'version': '1',
        'license': 'MIT',
        'size_bytes': contents.values
            .map((value) => utf8.encode(value).length)
            .fold<int>(0, (sum, value) => sum + value),
        'files': files,
      }),
    );
  }

  List<String> rootEntries() => modelsRoot
      .listSync()
      .map((e) => p.basename(e.path))
      .toList(growable: false);

  group('installFromDirectory', () {
    test('valid pack is copied and listed', () async {
      await writePack();
      final id = await manager.installFromDirectory(source.path);
      expect(id, 'whisper-tiny');
      expect(rootEntries(), ['whisper-tiny'], reason: 'нет .partial-остатков');
      expect(
        File(p.join(modelsRoot.path, id, 'encoder.int8.onnx')).existsSync(),
        isTrue,
      );

      final installed = await manager.listInstalled();
      expect(installed, hasLength(1));
      expect(installed.single.modelId, 'whisper-tiny');
      expect(installed.single.languages, ['ru', 'en']);
      expect(installed.single.engine, 'sherpa-onnx');
    });

    test(
      'hash mismatch -> ModelPackException, models dir stays clean',
      () async {
        await writePack(corruptHashOf: 'tokens.txt');
        await expectLater(
          manager.installFromDirectory(source.path),
          throwsA(isA<ModelPackException>()),
        );
        expect(rootEntries(), isEmpty);
      },
    );

    test(
      'missing pack file -> ModelPackException, models dir stays clean',
      () async {
        await writePack(omitFile: 'decoder.int8.onnx');
        await expectLater(
          manager.installFromDirectory(source.path),
          throwsA(isA<ModelPackException>()),
        );
        expect(rootEntries(), isEmpty);
      },
    );

    test('missing manifest -> ModelPackException', () async {
      await expectLater(
        manager.installFromDirectory(source.path),
        throwsA(isA<ModelPackException>()),
      );
    });

    test('rejects incompatible engine before copying', () async {
      await writePack();
      final manifestFile = File(
        p.join(source.path, AsrModelManager.manifestFileName),
      );
      final manifest = json.decode(await manifestFile.readAsString()) as Map;
      manifest['engine'] = 'other-engine';
      await manifestFile.writeAsString(json.encode(manifest));
      await expectLater(
        manager.installFromDirectory(source.path),
        throwsA(isA<ModelPackException>()),
      );
      expect(rootEntries(), isEmpty);
    });

    test(
      'imports official Whisper directory and pins selected int8 files',
      () async {
        await File(
          p.join(source.path, 'tiny-encoder.int8.onnx'),
        ).writeAsString('encoder-int8');
        await File(
          p.join(source.path, 'tiny-encoder.onnx'),
        ).writeAsString('encoder-fp32');
        await File(
          p.join(source.path, 'tiny-decoder.int8.onnx'),
        ).writeAsString('decoder-int8');
        await File(
          p.join(source.path, 'tiny-tokens.txt'),
        ).writeAsString('tokens');

        final id = await manager.installWhisperDirectory(source.path);
        final installed = await manager.installedManifest(id);

        expect(installed, isNotNull);
        expect(installed!.license, 'MIT');
        expect(installed.files.keys, {
          'tiny-encoder.int8.onnx',
          'tiny-decoder.int8.onnx',
          'tiny-tokens.txt',
        });
        expect(
          File(p.join(modelsRoot.path, id, 'tiny-encoder.onnx')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'descends into a single nested folder left by tar/zip extraction',
      () async {
        final nested = Directory(
          p.join(source.path, 'sherpa-onnx-whisper-base'),
        )..createSync();
        await File(
          p.join(nested.path, 'base-encoder.onnx'),
        ).writeAsString('encoder-fp32');
        await File(
          p.join(nested.path, 'base-decoder.onnx'),
        ).writeAsString('decoder-fp32');
        await File(
          p.join(nested.path, 'base-tokens.txt'),
        ).writeAsString('tokens');

        final id = await manager.installWhisperDirectory(source.path);
        final installed = await manager.installedManifest(id);

        expect(installed, isNotNull);
        expect(installed!.files.keys, {
          'base-encoder.onnx',
          'base-decoder.onnx',
          'base-tokens.txt',
        });
      },
    );

    test(
      'descends into the matching nested folder even with unrelated siblings',
      () async {
        Directory(p.join(source.path, 'empty-sibling')).createSync();
        final nested = Directory(
          p.join(source.path, 'sherpa-onnx-whisper-base'),
        )..createSync();
        await File(
          p.join(nested.path, 'base-encoder.int8.onnx'),
        ).writeAsString('encoder-int8');
        await File(
          p.join(nested.path, 'base-decoder.int8.onnx'),
        ).writeAsString('decoder-int8');
        await File(
          p.join(nested.path, 'base-tokens.txt'),
        ).writeAsString('tokens');

        final id = await manager.installWhisperDirectory(source.path);
        final installed = await manager.installedManifest(id);

        expect(installed, isNotNull);
        expect(installed!.files.keys, {
          'base-encoder.int8.onnx',
          'base-decoder.int8.onnx',
          'base-tokens.txt',
        });
      },
    );

    test(
      'ambiguous nested folders with model files are reported by name',
      () async {
        for (final name in ['base', 'small']) {
          final dir = Directory(p.join(source.path, name))..createSync();
          await File(
            p.join(dir.path, '$name-encoder.onnx'),
          ).writeAsString('encoder');
        }

        await expectLater(
          manager.installWhisperDirectory(source.path),
          throwsA(
            isA<ModelPackException>()
                .having((e) => e.message, 'message', contains('base'))
                .having((e) => e.message, 'message', contains('small')),
          ),
        );
      },
    );

    test(
      'error message lists the actual directory contents for diagnosis',
      () async {
        await File(
          p.join(source.path, 'notes.txt'),
        ).writeAsString('not a model');

        await expectLater(
          manager.installWhisperDirectory(source.path),
          throwsA(
            isA<ModelPackException>().having(
              (e) => e.message,
              'message',
              contains('notes.txt'),
            ),
          ),
        );
      },
    );

    test('picks up external-data companion files next to the graph', () async {
      await File(
        p.join(source.path, 'small-encoder.onnx'),
      ).writeAsString('encoder-graph');
      await File(
        p.join(source.path, 'small-encoder.onnx.data'),
      ).writeAsString('encoder-weights');
      await File(
        p.join(source.path, 'small-decoder.onnx'),
      ).writeAsString('decoder-graph');
      await File(
        p.join(source.path, 'small-tokens.txt'),
      ).writeAsString('tokens');

      final id = await manager.installWhisperDirectory(source.path);
      final installed = await manager.installedManifest(id);

      expect(installed, isNotNull);
      expect(installed!.files.keys, {
        'small-encoder.onnx',
        'small-encoder.onnx.data',
        'small-decoder.onnx',
        'small-tokens.txt',
      });
    });

    test('detects a NeMo-transducer pack (GigaAM/Parakeet) by joiner.onnx '
        'and installs it as nemo_transducer', () async {
      await File(
        p.join(source.path, 'encoder.int8.onnx'),
      ).writeAsString('encoder');
      await File(p.join(source.path, 'decoder.onnx')).writeAsString('decoder');
      await File(p.join(source.path, 'joiner.onnx')).writeAsString('joiner');
      await File(p.join(source.path, 'tokens.txt')).writeAsString('tokens');

      final id = await manager.installWhisperDirectory(source.path);
      final installed = await manager.installedManifest(id);

      expect(installed, isNotNull);
      expect(installed!.modelType, 'nemo_transducer');
      expect(installed.files.keys, {
        'encoder.int8.onnx',
        'decoder.onnx',
        'joiner.onnx',
        'tokens.txt',
      });

      // activate() должен принимать nemo_transducer, а не только whisper.
      await manager.activate(id);
      expect(await manager.activeModel(), id);
    });

    test('missing encoder lists what was actually found', () async {
      await File(
        p.join(source.path, 'unrelated-decoder.onnx'),
      ).writeAsString('decoder-fp32');

      await expectLater(
        manager.installWhisperDirectory(source.path),
        throwsA(
          isA<ModelPackException>().having(
            (e) => e.message,
            'message',
            contains('unrelated-decoder.onnx'),
          ),
        ),
      );
    });
  });

  group('activate / activeModelDir', () {
    test('activate re-verifies hashes and stores the key', () async {
      await writePack();
      final id = await manager.installFromDirectory(source.path);
      await manager.activate(id);
      expect(await manager.activeModel(), id);
      expect(await manager.activeModelDir(), p.join(modelsRoot.path, id));
    });

    test('activate rejects tampered installed pack, key unchanged', () async {
      await writePack();
      final id = await manager.installFromDirectory(source.path);
      await File(
        p.join(modelsRoot.path, id, 'tokens.txt'),
      ).writeAsString('tampered');
      await expectLater(
        manager.activate(id),
        throwsA(isA<ModelPackException>()),
      );
      expect(await manager.activeModel(), isNull);
      expect(await manager.activeModelDir(), isNull);
    });

    test('activate of a not-installed model fails', () async {
      await expectLater(
        manager.activate('nope'),
        throwsA(isA<ModelPackException>()),
      );
    });
  });

  group('listInstalled', () {
    test('skips broken folders without deleting them', () async {
      await writePack();
      await manager.installFromDirectory(source.path);
      final broken = Directory(p.join(modelsRoot.path, 'broken'))..createSync();
      await File(
        p.join(broken.path, AsrModelManager.manifestFileName),
      ).writeAsString('not a json');
      final noManifest = Directory(p.join(modelsRoot.path, 'empty'))
        ..createSync();

      final installed = await manager.listInstalled();
      expect(installed.map((m) => m.modelId), ['whisper-tiny']);
      expect(broken.existsSync(), isTrue);
      expect(noManifest.existsSync(), isTrue);
    });
  });

  group('deleteModel', () {
    test('removes the pack from disk', () async {
      await writePack();
      final id = await manager.installFromDirectory(source.path);
      expect(Directory(p.join(modelsRoot.path, id)).existsSync(), isTrue);

      await manager.deleteModel(id);

      expect(Directory(p.join(modelsRoot.path, id)).existsSync(), isFalse);
      expect(await manager.installedManifest(id), isNull);
    });

    test('clears the active-model selection when deleting it', () async {
      await writePack();
      final id = await manager.installFromDirectory(source.path);
      await manager.activate(id);
      expect(await manager.activeModel(), id);

      await manager.deleteModel(id);

      expect(await manager.activeModel(), isNull);
      expect(await manager.activeModelDir(), isNull);
    });

    test('deleting an uninstalled model_id is a no-op', () async {
      await manager.deleteModel('never-installed');
    });

    test('rejects an unsafe model_id without touching the disk', () async {
      await expectLater(
        manager.deleteModel('../escape'),
        throwsA(isA<ModelPackException>()),
      );
    });
  });

  group('downloadAndInstall', () {
    late HttpServer server;
    late String baseUrl;
    late Map<String, String> filePayloads;
    late Map<String, String> manifestHashes;

    setUp(() async {
      filePayloads = {
        'encoder.int8.onnx': 'encoder-bytes',
        'decoder.onnx': 'decoder-bytes',
        'joiner.onnx': 'joiner-bytes',
        'tokens.txt': 'tokens-bytes',
      };
      // Хэши в манифесте фиксируются один раз здесь — тест "hash mismatch"
      // потом меняет `filePayloads` для отдачи файлов, не трогая эту карту,
      // чтобы получить настоящее расхождение, а не самосогласованную пару.
      manifestHashes = {
        for (final entry in filePayloads.entries)
          entry.key: sha256.convert(utf8.encode(entry.value)).toString(),
      };
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://${server.address.address}:${server.port}';
      manager = AsrModelManager(
        modelsRoot: modelsRoot,
        settings: settings,
        allowedDownloadHosts: {server.address.address},
      );
      unawaited(
        server.forEach((request) async {
          final name = request.uri.pathSegments.last;
          if (name == 'potok-model.json') {
            request.response.write(
              json.encode({
                'model_id': 'downloaded-model',
                'engine': 'sherpa-onnx',
                'model_type': 'nemo_transducer',
                'languages': ['ru'],
                'version': '1',
                'license': 'MIT',
                'size_bytes': filePayloads.values
                    .map((v) => utf8.encode(v).length)
                    .fold<int>(0, (sum, v) => sum + v),
                'files': manifestHashes,
              }),
            );
          } else if (filePayloads.containsKey(name)) {
            request.response.write(filePayloads[name]);
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        }),
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('downloads the manifest and every file, then installs', () async {
      final progressValues = <double>[];
      final id = await manager.downloadAndInstall(
        '$baseUrl/potok-model.json',
        onProgress: progressValues.add,
      );

      expect(id, 'downloaded-model');
      final installed = await manager.installedManifest(id);
      expect(installed, isNotNull);
      expect(installed!.modelType, 'nemo_transducer');
      expect(installed.files.keys, filePayloads.keys.toSet());
      expect(progressValues, isNotEmpty);
      expect(progressValues.last, 1.0);
    });

    test('passes a stable model-and-file task id to every download', () async {
      final downloader = _RecordingModelFileDownloader(filePayloads);
      manager = AsrModelManager(
        modelsRoot: modelsRoot,
        settings: settings,
        allowedDownloadHosts: {server.address.address},
        fileDownloader: downloader,
      );

      await manager.downloadAndInstall('$baseUrl/potok-model.json');

      expect(
        downloader.taskIds,
        filePayloads.keys
            .map((name) => 'downloaded-model::$name')
            .toList(growable: false),
      );
    });

    test('rejects a manifest URL on a host outside the allowlist', () async {
      final other = AsrModelManager(modelsRoot: modelsRoot, settings: settings);
      await expectLater(
        other.downloadAndInstall('$baseUrl/potok-model.json'),
        throwsA(isA<ModelPackException>()),
      );
    });

    test('hash mismatch from a corrupted download is rejected', () async {
      // Манифест уже раздаёт hashes исходного содержимого; файл теперь
      // отдаёт другие байты — установка должна поймать несовпадение.
      filePayloads['tokens.txt'] = 'tampered-after-hash-computed';
      await expectLater(
        manager.downloadAndInstall('$baseUrl/potok-model.json'),
        throwsA(isA<ModelPackException>()),
      );
    });

    test(
      'a restarted process installs completed native tasks and clears intent',
      () async {
        final interruptedDownloader = _CompletingThenFailingDownloader(
          filePayloads,
        );
        manager = AsrModelManager(
          modelsRoot: modelsRoot,
          settings: settings,
          allowedDownloadHosts: {server.address.address},
          fileDownloader: interruptedDownloader,
        );

        await expectLater(
          manager.downloadInstallAndActivate('$baseUrl/potok-model.json'),
          throwsA(isA<StateError>()),
        );
        expect(
          await settings.get(AsrModelManager.pendingDownloadUrlKey),
          '$baseUrl/potok-model.json',
        );
        await server.close(force: true);

        final resumedDownloader = _RecordingModelFileDownloader(filePayloads);
        final restartedManager = AsrModelManager(
          modelsRoot: modelsRoot,
          settings: settings,
          allowedDownloadHosts: {Uri.parse(baseUrl).host},
          fileDownloader: resumedDownloader,
        );
        final recoveredId = await restartedManager.recoverPendingDownload();

        expect(recoveredId, 'downloaded-model');
        expect(resumedDownloader.taskIds, isEmpty);
        expect(await restartedManager.activeModelDir(), isNotNull);
        expect(
          await settings.get(AsrModelManager.pendingDownloadUrlKey),
          isNull,
        );
      },
    );
  });

  group('dev fallback (POTOK_ASR_MODEL_DIR)', () {
    test('used only when no active model and the dir exists', () async {
      final dev = AsrModelManager(
        modelsRoot: modelsRoot,
        settings: settings,
        devFallbackDir: source.path,
      );
      expect(await dev.activeModelDir(), source.path);

      await writePack();
      final id = await dev.installFromDirectory(source.path);
      await dev.activate(id);
      expect(
        await dev.activeModelDir(),
        p.join(modelsRoot.path, id),
        reason: 'активная модель имеет приоритет над fallback',
      );
    });

    test('no active model and no fallback -> null', () async {
      expect(await manager.activeModelDir(), isNull);
    });
  });
}

class _RecordingModelFileDownloader implements ModelFileDownloader {
  final Map<String, String> payloads;
  final List<String> taskIds = [];

  _RecordingModelFileDownloader(this.payloads);

  @override
  Future<void> download(
    Uri url,
    String destinationPath, {
    required String taskId,
    void Function(double progress, int bytesPerSecond)? onProgress,
  }) async {
    final name = url.pathSegments.last;
    final payload = payloads[name];
    if (payload == null) throw StateError('unexpected model file');
    taskIds.add(taskId);
    await File(destinationPath).writeAsString(payload);
    onProgress?.call(1, utf8.encode(payload).length);
  }
}

class _CompletingThenFailingDownloader implements ModelFileDownloader {
  final Map<String, String> payloads;
  bool _hasFailed = false;

  _CompletingThenFailingDownloader(this.payloads);

  @override
  Future<void> download(
    Uri url,
    String destinationPath, {
    required String taskId,
    void Function(double progress, int bytesPerSecond)? onProgress,
  }) async {
    final payload = payloads[url.pathSegments.last];
    if (payload == null) throw StateError('unexpected model file');
    await File(destinationPath).writeAsString(payload, flush: true);
    onProgress?.call(1, utf8.encode(payload).length);
    if (!_hasFailed) {
      _hasFailed = true;
      throw StateError('simulated Dart process interruption');
    }
  }
}
