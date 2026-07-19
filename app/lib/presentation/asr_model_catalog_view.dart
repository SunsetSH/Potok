import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/asr_model_catalog.dart';
import '../infrastructure/asr/model_manager.dart';
import 'providers.dart';
import 'theme.dart';

/// Список моделей каталога: статус, рейтинги, скачивание с прогрессом,
/// активация, удаление. Общий для настроек и первого запуска — обе точки
/// входа должны вести себя одинаково, без дублирования логики.
class AsrModelCatalogView extends ConsumerStatefulWidget {
  /// Вызывается после успешной активации любой модели (скачанной только что
  /// или ранее установленной). Первый запуск использует это, чтобы закрыть
  /// диалог выбора; в настройках коллбэк можно не задавать.
  final VoidCallback? onModelActivated;

  const AsrModelCatalogView({super.key, this.onModelActivated});

  @override
  ConsumerState<AsrModelCatalogView> createState() =>
      _AsrModelCatalogViewState();
}

class _AsrModelCatalogViewState extends ConsumerState<AsrModelCatalogView> {
  Set<String> _installedIds = {};
  String? _downloadingId;
  double _downloadProgress = 0;
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshInstalled());
  }

  Future<void> _refreshInstalled() async {
    final manager = await ref.read(modelManagerProvider.future);
    final installed = await manager.listInstalled();
    if (mounted) {
      setState(() => _installedIds = installed.map((m) => m.modelId).toSet());
    }
  }

  Future<void> _download(AsrModelCatalogEntry entry) async {
    setState(() {
      _downloadingId = entry.id;
      _downloadProgress = 0;
      _error = null;
    });
    try {
      final manager = await ref.read(modelManagerProvider.future);
      final modelId = await manager.downloadAndInstall(
        entry.manifestUrl,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      await manager.activate(modelId);
      final queue = await ref.read(transcriptionQueueProvider.future);
      await queue.kick();
      await _refreshInstalled();
      widget.onModelActivated?.call();
    } on ModelPackException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('model download failed: ${e.runtimeType}');
      if (mounted) setState(() => _error = 'Не удалось скачать модель');
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _activate(String modelId) async {
    setState(() {
      _busyId = modelId;
      _error = null;
    });
    try {
      final manager = await ref.read(modelManagerProvider.future);
      await manager.activate(modelId);
      final queue = await ref.read(transcriptionQueueProvider.future);
      await queue.kick();
      widget.onModelActivated?.call();
    } on ModelPackException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('model activate failed: ${e.runtimeType}');
      if (mounted) setState(() => _error = 'Не удалось активировать модель');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(String modelId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить модель?'),
        content: const Text('Файлы модели будут удалены с диска.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-model'),
            style: FilledButton.styleFrom(
              backgroundColor: PotokColors.of(dialogContext).danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final manager = await ref.read(modelManagerProvider.future);
      await manager.deleteModel(modelId);
      await _refreshInstalled();
    } catch (e) {
      debugPrint('model delete failed: ${e.runtimeType}');
      if (mounted) setState(() => _error = 'Не удалось удалить модель');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final active = ref.watch(activeAsrModelProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in asrModelCatalog)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CatalogModelTile(
              entry: entry,
              isActive: active?.modelId == entry.id,
              isInstalled: _installedIds.contains(entry.id),
              isBusy: _busyId == entry.id,
              downloadProgress: _downloadingId == entry.id
                  ? _downloadProgress
                  : null,
              onDownload: () => _download(entry),
              onActivate: () => _activate(entry.id),
              onDelete: () => _delete(entry.id),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 11, color: c.danger),
            ),
          ),
      ],
    );
  }
}

/// Карточка одной модели в каталоге: статус, рейтинги RU/иностранный/
/// скорость, действие (скачать с прогрессом / активировать / удалить).
class _CatalogModelTile extends StatelessWidget {
  final AsrModelCatalogEntry entry;
  final bool isActive;
  final bool isInstalled;
  final bool isBusy;

  /// non-null, когда именно эта модель сейчас скачивается (0..1).
  final double? downloadProgress;
  final VoidCallback onDownload;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  const _CatalogModelTile({
    required this.entry,
    required this.isActive,
    required this.isInstalled,
    required this.isBusy,
    required this.downloadProgress,
    required this.onDownload,
    required this.onActivate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final downloading = downloadProgress != null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isActive ? c.accentSoft : c.surface2,
        border: Border.all(color: isActive ? c.accent : c.line),
        borderRadius: BorderRadius.circular(c.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
              Text(
                '${(entry.sizeBytes / (1024 * 1024)).toStringAsFixed(0)} МБ',
                style: TextStyle(fontSize: 10, color: c.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.description,
            style: TextStyle(fontSize: 10, color: c.muted, height: 1.3),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _TierBadge(label: 'Русский', tier: entry.russian),
              _TierBadge(label: 'Иностранный', tier: entry.foreign),
              _TierBadge(label: 'Скорость', tier: entry.speed),
            ],
          ),
          const SizedBox(height: 8),
          if (downloading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: downloadProgress! > 0 ? downloadProgress : null,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(downloadProgress! * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 10, color: c.muted),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isInstalled)
                  TextButton.icon(
                    onPressed: entry.isDownloadable && !isBusy
                        ? onDownload
                        : null,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: Text(entry.isDownloadable ? 'Скачать' : 'Скоро'),
                  )
                else ...[
                  IconButton(
                    tooltip: 'Удалить модель',
                    onPressed: isBusy ? null : onDelete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: c.danger,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (isActive)
                    Text(
                      'Активна',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.accent,
                      ),
                    )
                  else
                    TextButton(
                      onPressed: isBusy ? null : onActivate,
                      child: const Text('Активировать'),
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// Рейтинг 1..3 звезды по одному из трёх измерений модели.
class _TierBadge extends StatelessWidget {
  final String label;
  final AsrQualityTier tier;

  const _TierBadge({required this.label, required this.tier});

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: c.muted)),
        const SizedBox(width: 4),
        for (var i = 1; i <= 3; i++)
          Icon(
            i <= tier.stars ? Icons.star_rounded : Icons.star_border_rounded,
            size: 11,
            color: i <= tier.stars ? c.accent : c.muted,
          ),
      ],
    );
  }
}
