import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/backup_service.dart';
import '../application/export_service.dart';
import '../application/restore_service.dart';
import 'providers.dart';
import 'theme.dart';

/// Раздел «Данные» в настройках: резервная копия, восстановление и экспорт.
/// Сообщения короткие и никогда не содержат текст заметок (ТЗ 0.10.2).
class DataSettingsSection extends ConsumerStatefulWidget {
  const DataSettingsSection({super.key});

  @override
  ConsumerState<DataSettingsSection> createState() =>
      _DataSettingsSectionState();
}

class _DataSettingsSectionState extends ConsumerState<DataSettingsSection> {
  bool _busy = false;

  // ---------- Backup ----------

  Future<void> _createBackup() async {
    final confirmed = await _confirm(
      title: 'Создать резервную копию?',
      body:
          'Копия сохраняется без шифрования: любой, у кого есть файл, '
          'сможет прочитать заметки и прослушать аудио.',
      action: 'Продолжить',
    );
    if (confirmed != true || !mounted) return;

    final now = DateTime.now();
    final stamp =
        '${now.year}${_p(now.month)}${_p(now.day)}-${_p(now.hour)}${_p(now.minute)}';
    final location = await getSaveLocation(
      suggestedName: 'potok-$stamp.${BackupFormat.fileExtension}',
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Резервная копия Потока',
          extensions: [BackupFormat.fileExtension],
        ),
      ],
    );
    if (location == null || !mounted) return;

    final progress = ValueNotifier<(int, int)>((0, 1));
    var cancelled = false;
    _showProgressDialog(
      title: 'Создание копии…',
      progress: progress,
      onCancel: () => cancelled = true,
    );
    setState(() => _busy = true);
    try {
      final service = await ref.read(backupServiceProvider.future);
      final result = await service.createBackup(
        targetPath: location.path,
        onProgress: (done, total) => progress.value = (done, total),
        isCancelled: () => cancelled,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // прогресс
      final missing = result.missingAssetCount > 0
          ? '\nПропущено отсутствующих файлов: ${result.missingAssetCount}.'
          : '';
      await _info(
        title: 'Копия создана',
        body:
            '${result.path}\n'
            'Размер: ${_formatBytes(result.sizeBytes)}. '
            'Заметок: ${result.noteCount}, файлов: ${result.assetCount}.'
            '$missing',
      );
    } on BackupCancelled {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on BackupException catch (e) {
      _failProgress('Не удалось создать копию: ${e.message}');
    } catch (e) {
      debugPrint('backup failed: ${e.runtimeType}');
      _failProgress('Не удалось создать копию');
    } finally {
      progress.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Restore ----------

  Future<void> _restore() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Резервная копия Потока',
          extensions: [BackupFormat.fileExtension],
        ),
      ],
    );
    if (file == null || !mounted) return;
    final confirmed = await _confirm(
      title: 'Восстановить из копии?',
      body:
          'Текущие данные будут заменены содержимым копии. '
          'Перед заменой будет создана страховочная копия текущих данных.',
      action: 'Восстановить',
    );
    if (confirmed != true || !mounted) return;

    final progress = ValueNotifier<(int, int)>((0, 1));
    var cancelled = false;
    _showProgressDialog(
      title: 'Восстановление…',
      progress: progress,
      onCancel: () => cancelled = true,
    );
    setState(() => _busy = true);
    RestoreCandidate? candidate;
    try {
      final service = await ref.read(restoreServiceProvider.future);
      candidate = await service.prepare(
        file.path,
        onProgress: (done, total) => progress.value = (done, total),
        isCancelled: () => cancelled,
      );
      // Кандидат проверен. Закрываем БД, меняем данные, переоткрываем.
      final db = ref.read(databaseProvider);
      await db.close();
      try {
        await service.apply(candidate);
        candidate = null;
      } finally {
        // Провайдер пересоздаёт AppDatabase поверх актуальных файлов —
        // и после успеха, и после отката.
        ref.invalidate(databaseProvider);
      }
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // прогресс
      Navigator.of(context).pop(); // диалог настроек: данные под ним устарели
      await _info(
        title: 'Данные восстановлены',
        body:
            'Восстановление завершено. Если списки не обновились, '
            'перезапустите приложение.',
      );
    } on RestoreCancelled {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on RestoreException catch (e) {
      _failProgress('Восстановление отклонено: ${e.message}');
    } catch (e) {
      debugPrint('restore failed: ${e.runtimeType}');
      _failProgress('Не удалось восстановить данные');
    } finally {
      if (candidate != null) {
        final service = await ref.read(restoreServiceProvider.future);
        await service.discard(candidate);
      }
      progress.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Export ----------

  Future<void> _export() async {
    final format = await showDialog<ExportFormat>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Формат экспорта'),
        children: [
          for (final format in ExportFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(format),
              child: Text('${format.label} (.${format.extension})'),
            ),
        ],
      ),
    );
    if (format == null || !mounted) return;

    final section = ref.read(navSectionProvider);
    if (section is TrashSection) {
      await _info(title: 'Экспорт', body: 'Корзина не экспортируется.');
      return;
    }
    final location = await getSaveLocation(
      suggestedName: 'potok-export.${format.extension}',
      acceptedTypeGroups: [
        XTypeGroup(label: format.label, extensions: [format.extension]),
      ],
    );
    if (location == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final service = await ref.read(exportServiceProvider.future);
      final settings = ref.read(noteListViewSettingsProvider);
      final notes = await service.collectNotes(
        projectId: switch (section) {
          ProjectSection(:final projectId) => projectId,
          _ => null,
        },
        onlyNoProject: section is NoProjectSection,
        onlyFavorites: section is FavoritesSection,
        filter: settings.filter,
        order: settings.order,
      );
      final bytes = switch (format) {
        ExportFormat.markdown => utf8.encode(
          await service.exportMarkdown(notes),
        ),
        ExportFormat.csv => await service.exportCsv(notes),
        ExportFormat.json => utf8.encode(await service.exportJson(notes)),
      };
      await File(location.path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await _info(
        title: 'Экспорт завершён',
        body: '${location.path}\nЗаметок: ${notes.length}.',
      );
    } catch (e) {
      debugPrint('export failed: ${e.runtimeType}');
      if (mounted) {
        await _info(title: 'Экспорт', body: 'Не удалось выполнить экспорт');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Вспомогательные диалоги ----------

  void _showProgressDialog({
    required String title,
    required ValueNotifier<(int, int)> progress,
    required VoidCallback onCancel,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, value, _) {
            final (done, total) = value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: total > 0 ? done / total : null),
                const SizedBox(height: 8),
                Text('Файлов: $done из $total'),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: onCancel, child: const Text('Отменить')),
        ],
      ),
    );
  }

  void _failProgress(String message) {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // прогресс
    unawaited(_info(title: 'Ошибка', body: message));
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _info({required String title, required String body}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SelectableText(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  static String _p(int value) => value.toString().padLeft(2, '0');

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '$bytes Б';
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        enabled: !_busy,
        leading: Icon(icon, size: 18, color: c.muted),
        title: Text(title, style: TextStyle(fontSize: 13, color: c.text)),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 11, color: c.muted),
        ),
        onTap: onTap,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile(
          icon: Icons.archive_outlined,
          title: 'Создать резервную копию…',
          subtitle: 'База и медиафайлы одним архивом (без шифрования)',
          onTap: _createBackup,
        ),
        tile(
          icon: Icons.settings_backup_restore_rounded,
          title: 'Восстановить из копии…',
          subtitle: 'Текущие данные будут заменены',
          onTap: _restore,
        ),
        tile(
          icon: Icons.ios_share_rounded,
          title: 'Экспорт раздела…',
          subtitle: 'Markdown, CSV или JSON для текущей выборки',
          onTap: _export,
        ),
      ],
    );
  }
}
