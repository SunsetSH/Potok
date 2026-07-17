import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../application/settings_service.dart';

/// Источник пути к активной модели для очереди расшифровки; отделяет
/// application-слой от деталей установки паков (тесты подменяют его).
abstract interface class ActiveModelLocator {
  /// Абсолютный путь к папке активной модели или null, если модели нет.
  Future<String?> activeModelDir();
}

/// Ожидаемая ошибка установки/активации model pack: повреждённый или
/// неполный пакет. [message] — короткий русский текст для UI (имена файлов
/// допустимы, содержимое — нет).
class ModelPackException implements Exception {
  final String message;
  const ModelPackException(this.message);

  @override
  String toString() => 'ModelPackException: $message';
}

/// Манифест model pack (ADR-002): `potok-model.json` в корне папки модели.
class ModelManifest {
  final String modelId;
  final String engine;
  final String modelType;
  final List<String> languages;
  final String version;

  /// Имя файла → ожидаемый SHA-256 (hex).
  final Map<String, String> files;

  const ModelManifest({
    required this.modelId,
    required this.engine,
    required this.modelType,
    required this.languages,
    required this.version,
    required this.files,
  });

  /// Имена без разделителей путей: манифест не может ссылаться наружу
  /// своей папки (path traversal).
  static final _safeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  static ModelManifest parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = json.decode(jsonText);
    } on FormatException {
      throw const ModelPackException('манифест повреждён (не JSON)');
    }
    if (decoded is! Map<String, Object?>) {
      throw const ModelPackException('манифест повреждён');
    }
    final modelId = decoded['model_id'];
    final engine = decoded['engine'];
    final modelType = decoded['model_type'];
    final version = decoded['version'];
    final languagesRaw = decoded['languages'];
    final filesRaw = decoded['files'];
    if (modelId is! String || !_safeName.hasMatch(modelId)) {
      throw const ModelPackException('манифест: некорректный model_id');
    }
    if (engine is! String || engine.isEmpty) {
      throw const ModelPackException('манифест: не указан engine');
    }
    if (modelType is! String ||
        languagesRaw is! List<Object?> ||
        version is! String) {
      throw const ModelPackException('манифест повреждён');
    }
    if (filesRaw is! Map<String, Object?> || filesRaw.isEmpty) {
      throw const ModelPackException('манифест: пустой список файлов');
    }
    final files = <String, String>{};
    for (final entry in filesRaw.entries) {
      final hash = entry.value;
      if (!_safeName.hasMatch(entry.key) || hash is! String || hash.isEmpty) {
        throw const ModelPackException('манифест: некорректная запись файла');
      }
      files[entry.key] = hash.toLowerCase();
    }
    return ModelManifest(
      modelId: modelId,
      engine: engine,
      modelType: modelType,
      languages: languagesRaw.whereType<String>().toList(growable: false),
      version: version,
      files: files,
    );
  }
}

/// Установка, проверка и активация локальных ASR model pack'ов (ADR-002).
///
/// Каталог: `<modelsRoot>/<model_id>/` с манифестом [manifestFileName].
/// Установка идёт через `<model_id>.partial` + атомарный rename, поэтому в
/// [modelsRoot] не бывает наполовину скопированных «валидных» паков.
class AsrModelManager implements ActiveModelLocator {
  static const manifestFileName = 'potok-model.json';
  static const activeModelKey = 'asr.active_model';
  static const _partialSuffix = '.partial';

  final Directory modelsRoot;
  final SettingsService settings;

  /// Временный dev-режим: папка модели без манифеста из POTOK_ASR_MODEL_DIR.
  /// Используется только если активной модели нет; только чтение.
  final String? devFallbackDir;

  AsrModelManager({
    required this.modelsRoot,
    required this.settings,
    this.devFallbackDir,
  });

  /// Проверяет пак в [sourceDir] (манифест + SHA-256 каждого файла),
  /// копирует его в каталог моделей и возвращает model_id.
  /// Повреждённый пак — [ModelPackException], каталог моделей не меняется.
  Future<String> installFromDirectory(String sourceDir) async {
    final source = Directory(sourceDir);
    if (!source.existsSync()) {
      throw const ModelPackException('папка модели не найдена');
    }
    final manifestFile = File(p.join(source.path, manifestFileName));
    if (!manifestFile.existsSync()) {
      throw const ModelPackException('манифест $manifestFileName не найден');
    }
    final manifest = ModelManifest.parse(await manifestFile.readAsString());

    await modelsRoot.create(recursive: true);
    final partial =
        Directory(p.join(modelsRoot.path, manifest.modelId + _partialSuffix));
    try {
      if (partial.existsSync()) {
        await partial.delete(recursive: true);
      }
      await partial.create(recursive: true);
      for (final entry in manifest.files.entries) {
        final sourceFile = File(p.join(source.path, entry.key));
        if (!sourceFile.existsSync()) {
          throw ModelPackException('в пакете нет файла ${entry.key}');
        }
        final copied =
            await sourceFile.copy(p.join(partial.path, entry.key));
        // Hash считается по копии: проверяем и исходник, и сам перенос.
        final actual = await _sha256Hex(copied);
        if (actual != entry.value) {
          throw ModelPackException(
              'контрольная сумма не совпадает: ${entry.key}');
        }
      }
      await manifestFile.copy(p.join(partial.path, manifestFileName));

      final target = Directory(p.join(modelsRoot.path, manifest.modelId));
      if (target.existsSync()) {
        // Переустановка: старую версию заменяет полностью проверенный пак.
        await target.delete(recursive: true);
      }
      await partial.rename(target.path);
      return manifest.modelId;
    } catch (e) {
      if (partial.existsSync()) {
        await partial.delete(recursive: true);
      }
      rethrow;
    }
  }

  /// Валидные установленные паки. Битые папки пропускаются, но не удаляются
  /// (диагностика вручную важнее самоочистки).
  Future<List<ModelManifest>> listInstalled() async {
    if (!modelsRoot.existsSync()) return const [];
    final manifests = <ModelManifest>[];
    await for (final entry in modelsRoot.list()) {
      if (entry is! Directory) continue;
      final name = p.basename(entry.path);
      if (name.endsWith(_partialSuffix)) continue;
      final manifest = await _readInstalledManifest(name);
      if (manifest != null) manifests.add(manifest);
    }
    manifests.sort((a, b) => a.modelId.compareTo(b.modelId));
    return manifests;
  }

  /// Манифест установленного пака или null, если пак отсутствует/битый.
  Future<ModelManifest?> installedManifest(String modelId) =>
      _readInstalledManifest(modelId);

  /// Делает модель активной. Контракт ТЗ: перед записью ключа SHA-256 всех
  /// файлов проверяется повторно; несовпадение — [ModelPackException],
  /// активная модель не меняется.
  Future<void> activate(String modelId) async {
    final dir = Directory(p.join(modelsRoot.path, modelId));
    final manifestFile = File(p.join(dir.path, manifestFileName));
    if (!manifestFile.existsSync()) {
      throw const ModelPackException('модель не установлена');
    }
    final manifest = ModelManifest.parse(await manifestFile.readAsString());
    for (final entry in manifest.files.entries) {
      final file = File(p.join(dir.path, entry.key));
      if (!file.existsSync()) {
        throw ModelPackException('в модели нет файла ${entry.key}');
      }
      final actual = await _sha256Hex(file);
      if (actual != entry.value) {
        throw ModelPackException(
            'контрольная сумма не совпадает: ${entry.key}');
      }
    }
    await settings.set(activeModelKey, modelId);
  }

  /// model_id активной модели (без проверки, что пак ещё на диске).
  Future<String?> activeModel() => settings.get(activeModelKey);

  @override
  Future<String?> activeModelDir() async {
    final id = await settings.get(activeModelKey);
    if (id != null) {
      final dir = Directory(p.join(modelsRoot.path, id));
      if (File(p.join(dir.path, manifestFileName)).existsSync()) {
        return dir.path;
      }
    }
    final dev = devFallbackDir;
    if (dev != null && dev.isNotEmpty && Directory(dev).existsSync()) {
      return dev;
    }
    return null;
  }

  Future<ModelManifest?> _readInstalledManifest(String dirName) async {
    final dir = Directory(p.join(modelsRoot.path, dirName));
    final manifestFile = File(p.join(dir.path, manifestFileName));
    if (!manifestFile.existsSync()) return null;
    final ModelManifest manifest;
    try {
      manifest = ModelManifest.parse(await manifestFile.readAsString());
    } on ModelPackException {
      return null;
    }
    if (manifest.modelId != dirName) return null;
    for (final name in manifest.files.keys) {
      if (!File(p.join(dir.path, name)).existsSync()) return null;
    }
    return manifest;
  }

  static Future<String> _sha256Hex(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
