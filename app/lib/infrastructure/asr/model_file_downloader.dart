import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart' as bg;
import 'package:path/path.dart' as p;

/// Скачивание одного файла модели за уже провалидированным (allowlist, все
/// редиректы проверены хоп за хопом) финальным URL. Реализация подменяема,
/// потому что обычный `HttpClient` внутри Dart-изолята останавливается вместе
/// с изолятом, когда Android приостанавливает приложение (Doze/App Standby
/// после сворачивания или блокировки экрана) — а нативный фоновый трансфер
/// [BackgroundModelFileDownloader] нет.
abstract interface class ModelFileDownloader {
  /// [onProgress] — доля 0..1 и мгновенная скорость в байт/сек (0, если
  /// неизвестна). [url] редиректы больше не проверяет — это уже сделано.
  Future<void> download(
    Uri url,
    String destinationPath, {
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
    void Function(double progress, int bytesPerSecond)? onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      // Финальный URL уже провалидирован вызывающей стороной — лишний
      // редирект здесь означает нестабильный сервер, а не что-то, что можно
      // молча обойти без повторной проверки allowlist.
      request.followRedirects = false;
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
                ((downloaded - lastBytes) * 1000000) ~/
                (elapsed - lastMicros);
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

/// Нативный фоновый трансфер через package:background_downloader: на Android
/// файл докачивается вне жизненного цикла Flutter-движка, поэтому сворачивание
/// приложения или блокировка экрана его не обрывают (см. ADR-013). На
/// Windows/desktop особого фонового режима не требуется — там и обычный
/// HttpClient не останавливается при сворачивании, но единый путь кода проще
/// одного набора багов, чем два.
class BackgroundModelFileDownloader implements ModelFileDownloader {
  @override
  Future<void> download(
    Uri url,
    String destinationPath, {
    void Function(double progress, int bytesPerSecond)? onProgress,
  }) async {
    final task = bg.DownloadTask(
      url: url.toString(),
      filename: p.basename(destinationPath),
      baseDirectory: bg.BaseDirectory.root,
      directory: p.dirname(destinationPath),
      updates: bg.Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
    );
    final done = Completer<bg.TaskStatusUpdate>();
    final subscription = bg.FileDownloader().updates.listen((update) {
      if (update.task.taskId != task.taskId) return;
      switch (update) {
        case bg.TaskProgressUpdate():
          if (onProgress == null || update.progress < 0) return;
          final speed = update.hasNetworkSpeed
              ? (update.networkSpeed * 1024 * 1024).round()
              : 0;
          onProgress(update.progress.clamp(0.0, 1.0), speed);
        case bg.TaskStatusUpdate():
          if (!done.isCompleted) done.complete(update);
      }
    });
    try {
      final enqueued = await bg.FileDownloader().enqueue(task);
      if (!enqueued) {
        throw Exception('couldn\'t enqueue background download task');
      }
      final result = await done.future;
      if (result.status != bg.TaskStatus.complete) {
        throw Exception('download failed: ${result.status}');
      }
    } finally {
      await subscription.cancel();
    }
  }
}
