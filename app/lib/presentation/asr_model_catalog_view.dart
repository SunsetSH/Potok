import 'dart:async';
import 'dart:io' show Platform;

import 'package:background_downloader/background_downloader.dart';
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
  int _downloadBytesPerSecond = 0;
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

  /// Уведомление о ходе фоновой загрузки — единственный способ показать
  /// прогресс, если пользователь свернул приложение или заблокировал экран
  /// (сама загрузка при этом продолжается, см. ADR-013). Без разрешения
  /// докачка всё равно идёт, просто без уведомления — поэтому результат
  /// запроса не блокирует скачивание.
  Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid) return;
    final status = await FileDownloader().permissions.status(
      PermissionType.notifications,
    );
    if (status != PermissionStatus.granted) {
      await FileDownloader().permissions.request(PermissionType.notifications);
    }
  }

  Future<void> _download(AsrModelCatalogEntry entry) async {
    setState(() {
      _downloadingId = entry.id;
      _downloadProgress = 0;
      _downloadBytesPerSecond = 0;
      _error = null;
    });
    try {
      await _ensureNotificationPermission();
      final manager = await ref.read(modelManagerProvider.future);
      await manager.downloadInstallAndActivate(
        entry.manifestUrl,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
        onSpeed: (bytesPerSecond) {
          if (mounted) {
            setState(() => _downloadBytesPerSecond = bytesPerSecond);
          }
        },
      );
      final queue = await ref.read(transcriptionQueueProvider.future);
      await queue.kick();
      await _refreshInstalled();
      widget.onModelActivated?.call();
    } on ModelPackException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, stackTrace) {
      // Privacy-safe release diagnostics: retain only Potok source frames.
      // Exception messages may contain filesystem paths, so never log them.
      final sourceFrames = stackTrace
          .toString()
          .split('\n')
          .where((line) => line.contains('package:potok/'))
          .take(4)
          .join(' | ');
      debugPrint(
        'model download failed: ${e.runtimeType}'
        '${sourceFrames.isEmpty ? '' : ' at $sourceFrames'}',
      );
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
    final pendingUrl = ref.watch(pendingAsrDownloadUrlProvider).value;
    final recovery = ref.watch(asrDownloadRecoveryProvider);
    ref.listen(asrDownloadRecoveryProvider, (_, next) {
      if (next.hasValue && next.value != null) {
        unawaited(_refreshInstalled());
        widget.onModelActivated?.call();
      }
    });
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
              isRecovering:
                  pendingUrl == entry.manifestUrl && recovery.isLoading,
              recoveryFailed:
                  pendingUrl == entry.manifestUrl && recovery.hasError,
              downloadProgress: _downloadingId == entry.id
                  ? _downloadProgress
                  : null,
              downloadBytesPerSecond: _downloadingId == entry.id
                  ? _downloadBytesPerSecond
                  : 0,
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
  final bool isRecovering;
  final bool recoveryFailed;

  /// non-null, когда именно эта модель сейчас скачивается (0..1).
  final double? downloadProgress;
  final int downloadBytesPerSecond;
  final VoidCallback onDownload;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  const _CatalogModelTile({
    required this.entry,
    required this.isActive,
    required this.isInstalled,
    required this.isBusy,
    required this.isRecovering,
    required this.recoveryFailed,
    required this.downloadProgress,
    required this.downloadBytesPerSecond,
    required this.onDownload,
    required this.onActivate,
    required this.onDelete,
  });

  static String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} МБ/с';
    }
    if (bytesPerSecond >= 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(0)} КБ/с';
    }
    return '$bytesPerSecond Б/с';
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final downloading = downloadProgress != null || isRecovering;
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
                    value: isRecovering ? null : downloadProgress,
                    minHeight: 6,
                    backgroundColor: c.line,
                    valueColor: AlwaysStoppedAnimation(c.accent),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      isRecovering
                          ? 'Восстановление фоновой загрузки…'
                          : '${(downloadProgress! * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 10, color: c.muted),
                    ),
                    if (downloadBytesPerSecond > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        _formatSpeed(downloadBytesPerSecond),
                        style: TextStyle(fontSize: 10, color: c.muted),
                      ),
                    ],
                  ],
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (recoveryFailed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'Фоновая загрузка не завершена',
                      style: TextStyle(fontSize: 10, color: c.danger),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isInstalled)
                      TextButton.icon(
                        onPressed: entry.isDownloadable && !isBusy
                            ? onDownload
                            : null,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: Text(
                          entry.isDownloadable
                              ? recoveryFailed
                                    ? 'Повторить'
                                    : 'Скачать'
                              : 'Скоро',
                        ),
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
