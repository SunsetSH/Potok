import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart' as bg;

/// Скачивание одного файла модели за уже провалидированным (allowlist, все
/// редиректы проверены хоп за хопом) финальным URL. Реализация подменяема,
/// потому что обычный `HttpClient` внутри Dart-изолята останавливается вместе
/// с изолятом, когда Android приостанавливает приложение (Doze/App Standby
/// после сворачивания или блокировки экрана) — а нативный фоновый трансфер
/// [BackgroundModelFileDownloader] нет.
abstract interface class ModelFileDownloader {
  /// [taskId] — стабильный идентификатор именно этого файла именно этой
  /// модели (например, `'gigaam-v3::encoder.int8.onnx'`): по нему
  /// [BackgroundModelFileDownloader] находит уже идущую или уже завершённую
  /// загрузку, если процесс приложения был убит и перезапущен посреди
  /// скачивания — не начинает заново и не плодит вторую параллельную задачу.
  /// [onProgress] — доля 0..1 и мгновенная скорость в байт/сек (0, если
  /// неизвестна). [url] редиректы больше не проверяет — это уже сделано.
  Future<void> download(
    Uri url,
    String destinationPath, {
    required String taskId,
    void Function(double progress, int bytesPerSecond)? onProgress,
  });
}

/// Простой `HttpClient` без платформенных каналов — единственная реализация,
/// доступная в `flutter test` без регистрации плагина. Используется как
/// значение по умолчанию в [AsrModelManager], чтобы юнит-тесты оставались
/// чистым Dart-кодом; в приложении явно подменяется на
/// [BackgroundModelFileDownloader].
class HttpClientModelFileDownloader implements ModelFileDownloader {
  @override
  Future<void> download(
    Uri url,
    String destinationPath, {
    required String taskId,
    void Function(double progress, int bytesPerSecond)? onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      // Следуем редиректам: github.com/releases/download/… ведёт на
      // подписанный CDN-URL. Хост входа уже провалидирован вызывающей
      // стороной, а целостность гарантирует последующая SHA-256 проверка.
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw Exception('download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength > 0 ? response.contentLength : 0;
      final sink = File(destinationPath).openWrite();
      var downloaded = 0;
      final stopwatch = Stopwatch()..start();
      var lastBytes = 0;
      var lastMicros = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          downloaded += chunk.length;
          final elapsed = stopwatch.elapsedMicroseconds;
          if (onProgress != null &&
              total > 0 &&
              elapsed - lastMicros >= 300000) {
            final bytesPerSecond =
                ((downloaded - lastBytes) * 1000000) ~/ (elapsed - lastMicros);
            onProgress(downloaded / total, bytesPerSecond);
            lastBytes = downloaded;
            lastMicros = elapsed;
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      onProgress?.call(1.0, 0);
    } finally {
      client.close(force: true);
    }
  }
}

/// Нативный фоновый трансфер через package:background_downloader.
///
/// Два независимых требования и как каждое из них закрыто:
/// 1. Байты должны продолжать скачиваться, когда Android приостанавливает
///    Flutter-движок (сворачивание, блокировка экрана, слабый канал —
///    контроль ОС может занять минуты). Это даёт нативный WorkManager-таск
///    ([bg.FileDownloader().enqueue]) — он не зависит от того, жив ли
///    Dart-изолят. `directory`/`baseDirectory` намеренно НЕ [bg.BaseDirectory
///    .root] с абсолютным путём — пакет прямо предупреждает, что абсолютный
///    путь может стать невалидным, если загрузка завершается, пока
///    приложение свёрнуто/выгружено ОС; берём управляемый
///    [bg.BaseDirectory.applicationSupport], который пакет сам корректно
///    резолвит в любой момент жизни процесса.
/// 2. Если процесс приложения полностью убит ОС (не просто свёрнут) —
///    Dart-объект [Completer] внутри текущего вызова гибнет вместе с
///    изолятом и никогда не досчитает до конца, даже если нативная загрузка
///    успешно завершилась. Поэтому у задачи стабильный [taskId], и при
///    повторном вызове (следующий запуск приложения) мы сначала смотрим
///    персистентную БД пакета — если файл уже докачан, копируем его без
///    повторного скачивания; если ещё идёт/на паузе — просто переподписываемся
///    на обновления вместо повторного enqueue.
class BackgroundModelFileDownloader implements ModelFileDownloader {
  static const _group = 'asr-model-download';
  static const _directory = 'asr_model_downloads';

  /// `FileDownloader.updates` is a single-subscription stream. A model pack
  /// downloads several files sequentially, so subscribing directly for each
  /// file makes the second one fail with "Stream has already been listened
  /// to". Keep exactly one native subscription and multiplex it for every
  /// current/future file task in this process.
  static final Stream<bg.TaskUpdate> _updates = bg.FileDownloader().updates
      .asBroadcastStream();

  @override
  Future<void> download(
    Uri url,
    String destinationPath, {
    required String taskId,
    void Function(double progress, int bytesPerSecond)? onProgress,
  }) async {
    // taskId идёт и в нативный идентификатор задачи (WorkManager tag /
    // URLSession id), и в имя файла — оставляем только безопасные символы,
    // детерминированно (чтобы резюм после перезапуска нашёл ту же задачу).
    final id = _safeId(taskId);
    final downloader = bg.FileDownloader();

    var existing = await downloader.database.recordForId(id);
    if (existing != null && existing.status.isFinalState) {
      if (existing.status == bg.TaskStatus.complete) {
        final donePath = await existing.task.filePath();
        if (File(donePath).existsSync()) {
          await _finish(existing.task, destinationPath, id);
          return;
        }
      }
      // failed/canceled и complete без файла нельзя оставлять под стабильным
      // taskId: новая попытка иначе увидит старый финальный статус как свой.
      await downloader.database.deleteRecordWithId(id);
      existing = null;
    }

    final task = bg.DownloadTask(
      taskId: id,
      url: url.toString(),
      filename: '$id.part',
      baseDirectory: bg.BaseDirectory.applicationSupport,
      directory: _directory,
      updates: bg.Updates.statusAndProgress,
      // followRedirects по умолчанию включён — стабильный github.com-URL
      // сам ведёт на подписанный CDN свежим GET, без нашего пред-резолва.
      allowPause: true,
      retries: 5,
      group: _group,
    );
    final done = Completer<_DownloadOutcome>();
    final subscription = _updates.listen((update) {
      if (update.task.taskId != id) return;
      switch (update) {
        case bg.TaskProgressUpdate():
          if (onProgress == null || update.progress < 0) return;
          final speed = update.hasNetworkSpeed
              ? (update.networkSpeed * 1024 * 1024).round()
              : 0;
          onProgress(update.progress.clamp(0.0, 1.0), speed);
        case bg.TaskStatusUpdate():
          if (update.status.isFinalState && !done.isCompleted) {
            done.complete((
              task: update.task,
              status: update.status,
              exception: update.exception,
            ));
          }
      }
    });
    try {
      var refreshed = existing ?? await downloader.database.recordForId(id);
      if (refreshed != null && refreshed.status.isFinalState) {
        // Финал мог успеть записаться между первой проверкой и подпиской.
        if (refreshed.status == bg.TaskStatus.complete) {
          final donePath = await refreshed.task.filePath();
          if (File(donePath).existsSync()) {
            await _finish(refreshed.task, destinationPath, id);
            return;
          }
        }
        await downloader.database.deleteRecordWithId(id);
        refreshed = null;
      }
      final alreadyInFlight =
          refreshed != null &&
          const {
            bg.TaskStatus.enqueued,
            bg.TaskStatus.running,
            bg.TaskStatus.paused,
            bg.TaskStatus.waitingToRetry,
          }.contains(refreshed.status);
      if (!alreadyInFlight) {
        final enqueued = await downloader.enqueue(task);
        if (!enqueued) {
          // WorkManager may already own this stable taskId while its database
          // record has not been restored yet (process restart race). In that
          // case enqueue correctly returns false; attach to the native task
          // instead of reporting a spurious download failure.
          final nativeTask = await downloader.taskForId(id);
          if (nativeTask == null) {
            throw Exception('could not enqueue background download task');
          }
        }
      }
      // Однократное чтение сразу после enqueue гонялось со старой записью БД.
      // Периодическая сверка также подхватывает финал, полученный нативной
      // задачей во время приостановки Flutter-движка.
      final result = await _waitForFinalState(downloader, id, done);
      if (result.status != bg.TaskStatus.complete) {
        final reason = result.exception?.description ?? '${result.status}';
        await downloader.database.deleteRecordWithId(id);
        throw Exception('background download failed: $reason');
      }
      await _finish(result.task, destinationPath, id);
    } finally {
      await subscription.cancel();
    }
  }

  Future<_DownloadOutcome> _waitForFinalState(
    bg.FileDownloader downloader,
    String id,
    Completer<_DownloadOutcome> liveOutcome,
  ) async {
    while (!liveOutcome.isCompleted) {
      await Future.any<void>([
        liveOutcome.future.then((_) {}),
        Future<void>.delayed(const Duration(seconds: 1)),
      ]);
      if (liveOutcome.isCompleted) break;
      final record = await downloader.database.recordForId(id);
      // The live status callback can complete the same Completer while the
      // database lookup above is awaiting. Re-check after the await: without
      // this guard a successful native download intermittently surfaced as
      // `StateError: Future already completed` and the whole model install
      // was reported as failed.
      if (!liveOutcome.isCompleted &&
          record != null &&
          record.status.isFinalState) {
        liveOutcome.complete((
          task: record.task,
          status: record.status,
          exception: record.exception,
        ));
      }
    }
    return liveOutcome.future;
  }

  Future<void> _finish(
    bg.Task nativeTask,
    String destinationPath,
    String id,
  ) async {
    final path = await nativeTask.filePath();
    await File(path).copy(destinationPath);
    try {
      await File(path).delete();
    } catch (_) {
      // Managed-файл не критичен: install идёт из destinationPath, а запись
      // БД мы всё равно удаляем ниже. Оставшийся .part подчистит ОС/переустан.
    }
    await bg.FileDownloader().database.deleteRecordWithId(id);
  }

  /// Идентификатор задачи и имя файла: только `[A-Za-z0-9._-]`, остальное →
  /// `_`. Детерминированно, поэтому резюм после перезапуска процесса находит
  /// ту же задачу по тому же id.
  static String _safeId(String taskId) =>
      taskId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

/// Финальный итог загрузки из любого источника (живое событие или запись БД)
/// — обе стороны дают task/status/exception, нужные для завершения и ошибки.
typedef _DownloadOutcome = ({
  bg.Task task,
  bg.TaskStatus status,
  bg.TaskException? exception,
});
