import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:potok/application/settings_service.dart';
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
    await File(p.join(source.path, AsrModelManager.manifestFileName))
        .writeAsString(json.encode({
      'model_id': modelId,
      'engine': 'sherpa-onnx',
      'model_type': 'whisper',
      'languages': ['ru', 'en'],
      'version': '1',
      'files': files,
    }));
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
      expect(rootEntries(), ['whisper-tiny'],
          reason: 'нет .partial-остатков');
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

    test('hash mismatch -> ModelPackException, models dir stays clean',
        () async {
      await writePack(corruptHashOf: 'tokens.txt');
      await expectLater(
        manager.installFromDirectory(source.path),
        throwsA(isA<ModelPackException>()),
      );
      expect(rootEntries(), isEmpty);
    });

    test('missing pack file -> ModelPackException, models dir stays clean',
        () async {
      await writePack(omitFile: 'decoder.int8.onnx');
      await expectLater(
        manager.installFromDirectory(source.path),
        throwsA(isA<ModelPackException>()),
      );
      expect(rootEntries(), isEmpty);
    });

    test('missing manifest -> ModelPackException', () async {
      await expectLater(
        manager.installFromDirectory(source.path),
        throwsA(isA<ModelPackException>()),
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
      await File(p.join(modelsRoot.path, id, 'tokens.txt'))
          .writeAsString('tampered');
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
      final broken = Directory(p.join(modelsRoot.path, 'broken'))
        ..createSync();
      await File(p.join(broken.path, AsrModelManager.manifestFileName))
          .writeAsString('not a json');
      final noManifest = Directory(p.join(modelsRoot.path, 'empty'))
        ..createSync();

      final installed = await manager.listInstalled();
      expect(installed.map((m) => m.modelId), ['whisper-tiny']);
      expect(broken.existsSync(), isTrue);
      expect(noManifest.existsSync(), isTrue);
    });
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
      expect(await dev.activeModelDir(), p.join(modelsRoot.path, id),
          reason: 'активная модель имеет приоритет над fallback');
    });

    test('no active model and no fallback -> null', () async {
      expect(await manager.activeModelDir(), isNull);
    });
  });
}
