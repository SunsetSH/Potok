import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'model_manager.dart';

/// Copies the verified model shipped in Flutter assets into writable managed
/// storage. Installation is lazy/staged and never overwrites a user choice.
class BundledModelInstaller {
  static const modelId = 'sherpa-onnx-whisper-tiny-bundled';
  static const _assetRoot = 'assets/models/default';
  static const _files = [
    AsrModelManager.manifestFileName,
    'tiny-decoder.int8.onnx',
    'tiny-encoder.int8.onnx',
    'tiny-tokens.txt',
  ];

  final AssetBundle assets;

  BundledModelInstaller({AssetBundle? assets}) : assets = assets ?? rootBundle;

  Future<void> ensureInstalled(AsrModelManager manager) async {
    final selected = await manager.activeModel();
    if (selected != null && await manager.activeModelDir() != null) return;

    final installed = await manager.installedManifest(modelId);
    if (installed != null) {
      try {
        await manager.activate(modelId);
        return;
      } on ModelPackException {
        // Битый установленный bundled-пак не должен блокировать bootstrap
        // навсегда: удаляем и переустанавливаем из assets.
        final broken = Directory(p.join(manager.modelsRoot.path, modelId));
        if (broken.existsSync()) {
          await broken.delete(recursive: true);
        }
      }
    }

    final bootstrapRoot = Directory(
      p.join(manager.modelsRoot.parent.path, 'model-bootstrap.partial'),
    );
    final source = Directory(p.join(bootstrapRoot.path, modelId));
    try {
      if (bootstrapRoot.existsSync()) {
        await bootstrapRoot.delete(recursive: true);
      }
      await source.create(recursive: true);
      for (final name in _files) {
        final data = await assets.load('$_assetRoot/$name');
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final partial = File(p.join(source.path, '$name.partial'));
        await partial.writeAsBytes(bytes, flush: true);
        await partial.rename(p.join(source.path, name));
      }
      final installedId = await manager.installFromDirectory(source.path);
      await manager.activate(installedId);
    } on FlutterError catch (error) {
      throw ModelPackException(
        'встроенная модель отсутствует в сборке (${error.runtimeType})',
      );
    } finally {
      if (bootstrapRoot.existsSync()) {
        await bootstrapRoot.delete(recursive: true);
      }
    }
  }
}
