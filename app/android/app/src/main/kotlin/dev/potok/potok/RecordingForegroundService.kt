package dev.potok.potok

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.StatFs
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import kotlin.concurrent.thread
import kotlin.math.min

/**
 * Foreground contract for both Flutter-owned capture and the native one-tap
 * widget recorder. Widget audio is staged in a private inbox; this adapter
 * never opens the application's SQLite database.
 */
class RecordingForegroundService : Service() {
    companion object {
        const val ACTION_UI_ACTIVE = "dev.potok.action.RECORDING_UI_ACTIVE"
        const val ACTION_UI_INACTIVE = "dev.potok.action.RECORDING_UI_INACTIVE"
        const val ACTION_WIDGET_TOGGLE = "dev.potok.action.RECORDING_WIDGET_TOGGLE"
        const val ACTION_WIDGET_STOP = "dev.potok.action.RECORDING_WIDGET_STOP"

        private const val channelId = "potok_recording"
        private const val notificationId = 1401
        private const val sampleRateHz = 16_000
        private const val channels = 1
        private const val bytesPerSample = 2
        private const val wavHeaderBytes = 44L
        private const val maxDurationSeconds = 30 * 60L
        private const val maxAudioBytes = sampleRateHz * channels * bytesPerSample * maxDurationSeconds
        private const val freeSpaceReserveBytes = 50L * 1024 * 1024
        private const val inboxName = "widget_recording_inbox"

        fun isWidgetRecording(context: Context): Boolean =
            context.getSharedPreferences(LaunchActions.WIDGET_PREFS, Context.MODE_PRIVATE)
                .getBoolean(LaunchActions.WIDGET_VOICE_RECORDING_ACTIVE, false)

        fun widgetStatus(context: Context): String =
            context.getSharedPreferences(LaunchActions.WIDGET_PREFS, Context.MODE_PRIVATE)
                .getString(LaunchActions.WIDGET_VOICE_RECORDING_STATUS, "ready") ?: "ready"
    }

    private class WidgetSession(
        val id: String,
        val partialFile: File,
        val recorder: AudioRecord,
        val startedAtUtc: Long,
    ) {
        @Volatile var running = true
        lateinit var worker: Thread
    }

    @Volatile private var widgetSession: WidgetSession? = null
    private var uiRecordingActive = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        recoverInterruptedRecordings()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_UI_ACTIVE -> startUiContract()
            ACTION_UI_INACTIVE -> stopUiContract()
            ACTION_WIDGET_TOGGLE -> {
                if (widgetSession != null || isWidgetRecording(this)) {
                    ensureForeground(buildWidgetNotification())
                    stopWidgetRecording()
                } else {
                    ensureForeground(buildWidgetNotification())
                    startWidgetRecording()
                }
            }
            ACTION_WIDGET_STOP -> {
                ensureForeground(buildWidgetNotification())
                stopWidgetRecording()
            }
            else -> stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        widgetSession?.let { stopWidgetRecording() }
        super.onDestroy()
    }

    private fun startUiContract() {
        if (widgetSession != null || isWidgetRecording(this)) return
        uiRecordingActive = true
        ensureForeground(buildUiNotification())
    }

    private fun stopUiContract() {
        uiRecordingActive = false
        if (widgetSession == null && !isWidgetRecording(this)) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun startWidgetRecording() {
        if (uiRecordingActive || widgetSession != null) {
            setWidgetState(false, "busy")
            finishForegroundIfIdle()
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            setWidgetState(false, "permission")
            finishForegroundIfIdle()
            return
        }
        val available = StatFs(filesDir.absolutePath).availableBytes
        if (available < maxAudioBytes + freeSpaceReserveBytes) {
            setWidgetState(false, "storage")
            finishForegroundIfIdle()
            return
        }

        val minimum = AudioRecord.getMinBufferSize(
            sampleRateHz,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minimum <= 0) {
            setWidgetState(false, "device")
            finishForegroundIfIdle()
            return
        }

        val recorder = createRecorder(minimum, MediaRecorder.AudioSource.VOICE_RECOGNITION)
            ?: createRecorder(minimum, MediaRecorder.AudioSource.MIC)
        if (recorder == null) {
            setWidgetState(false, "device")
            finishForegroundIfIdle()
            return
        }

        val inbox = inboxDirectory().apply { mkdirs() }
        val id = UUID.randomUUID().toString()
        val session = WidgetSession(
            id = id,
            partialFile = File(inbox, "$id.wav.partial"),
            recorder = recorder,
            startedAtUtc = System.currentTimeMillis(),
        )
        try {
            recorder.startRecording()
            if (recorder.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                throw IllegalStateException("AudioRecord did not enter recording state")
            }
        } catch (_: RuntimeException) {
            recorder.release()
            setWidgetState(false, "device")
            finishForegroundIfIdle()
            return
        }

        widgetSession = session
        setWidgetState(true, "recording")
        val bufferSize = (minimum * 2).coerceAtLeast(4096)
        session.worker = thread(name = "potok-widget-recorder") {
            recordPcm(session, bufferSize)
        }
    }

    private fun createRecorder(minimum: Int, audioSource: Int): AudioRecord? {
        val recorder = try {
            AudioRecord.Builder()
                .setAudioSource(audioSource)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRateHz)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(minimum * 2)
                .build()
        } catch (_: SecurityException) {
            return null
        } catch (_: RuntimeException) {
            return null
        }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            return null
        }
        return recorder
    }

    private fun recordPcm(session: WidgetSession, bufferSize: Int) {
        var failure = false
        try {
            RandomAccessFile(session.partialFile, "rw").use { output ->
                output.setLength(0)
                output.write(ByteArray(wavHeaderBytes.toInt()))
                val buffer = ByteArray(bufferSize)
                var written = 0L
                while (session.running && written < maxAudioBytes) {
                    val request = min(buffer.size.toLong(), maxAudioBytes - written).toInt()
                    val read = session.recorder.read(buffer, 0, request, AudioRecord.READ_BLOCKING)
                    if (read > 0) {
                        output.write(buffer, 0, read)
                        written += read
                    } else if (read < 0 && session.running) {
                        failure = true
                        break
                    }
                }
                output.fd.sync()
            }
        } catch (_: Exception) {
            failure = true
        } finally {
            if (failure || session.running) {
                mainHandler.post { stopWidgetRecording() }
            }
        }
    }

    private fun stopWidgetRecording() {
        val session = widgetSession
        widgetSession = null
        if (session == null) {
            recoverInterruptedRecordings()
            setWidgetState(false, "ready")
            finishForegroundIfIdle()
            return
        }

        session.running = false
        try {
            if (session.recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                session.recorder.stop()
            }
        } catch (_: IllegalStateException) {
            // The worker still flushes any complete frames already returned.
        }
        try {
            session.worker.join(2_000)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        session.recorder.release()

        val saved = finalizePartial(session.partialFile, session.id, session.startedAtUtc)
        setWidgetState(false, if (saved) "ready" else "error")
        if (saved) MainActivity.notifyWidgetRecordingAvailable()
        finishForegroundIfIdle()
    }

    private fun recoverInterruptedRecordings() {
        val inbox = inboxDirectory()
        if (!inbox.isDirectory) {
            setWidgetState(false, "ready")
            return
        }
        inbox.listFiles { file -> file.name.endsWith(".wav.partial") }
            .orEmpty()
            .take(8)
            .forEach { partial ->
                val id = partial.name.removeSuffix(".wav.partial")
                if (id.matches(Regex("^[A-Za-z0-9-]{1,64}$"))) {
                    if (finalizePartial(partial, id, partial.lastModified())) {
                        MainActivity.notifyWidgetRecordingAvailable()
                    }
                } else {
                    partial.delete()
                }
            }
        setWidgetState(false, "ready")
    }

    private fun finalizePartial(partial: File, id: String, createdAtUtc: Long): Boolean {
        if (!partial.isFile || partial.length() <= wavHeaderBytes) {
            partial.delete()
            return false
        }
        return try {
            val audioBytes = partial.length() - wavHeaderBytes
            RandomAccessFile(partial, "rw").use { file ->
                file.seek(0)
                file.write(wavHeader(audioBytes))
                file.fd.sync()
            }
            val target = File(partial.parentFile, "$id.wav")
            if (target.exists()) target.delete()
            check(partial.renameTo(target))
            val durationMs = audioBytes * 1000L /
                (sampleRateHz * channels * bytesPerSample)
            val metadata = JSONObject()
                .put("schemaVersion", 1)
                .put("id", id)
                .put("file", target.name)
                .put("durationMs", durationMs)
                .put("sampleRateHz", sampleRateHz)
                .put("channels", channels)
                .put("createdAtUtc", createdAtUtc.coerceAtLeast(0))
            val metadataPartial = File(partial.parentFile, "$id.json.partial")
            metadataPartial.writeText(metadata.toString(), Charsets.UTF_8)
            RandomAccessFile(metadataPartial, "rw").use { it.fd.sync() }
            val metadataTarget = File(partial.parentFile, "$id.json")
            if (metadataTarget.exists()) metadataTarget.delete()
            check(metadataPartial.renameTo(metadataTarget))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun wavHeader(audioBytes: Long): ByteArray {
        val byteRate = sampleRateHz * channels * bytesPerSample
        return ByteBuffer.allocate(wavHeaderBytes.toInt())
            .order(ByteOrder.LITTLE_ENDIAN)
            .put("RIFF".toByteArray(Charsets.US_ASCII))
            .putInt((audioBytes + 36).coerceAtMost(0xffffffffL).toInt())
            .put("WAVE".toByteArray(Charsets.US_ASCII))
            .put("fmt ".toByteArray(Charsets.US_ASCII))
            .putInt(16)
            .putShort(1)
            .putShort(channels.toShort())
            .putInt(sampleRateHz)
            .putInt(byteRate)
            .putShort((channels * bytesPerSample).toShort())
            .putShort((bytesPerSample * 8).toShort())
            .put("data".toByteArray(Charsets.US_ASCII))
            .putInt(audioBytes.coerceAtMost(0xffffffffL).toInt())
            .array()
    }

    private fun setWidgetState(active: Boolean, status: String) {
        getSharedPreferences(LaunchActions.WIDGET_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(LaunchActions.WIDGET_VOICE_RECORDING_ACTIVE, active)
            .putString(LaunchActions.WIDGET_VOICE_RECORDING_STATUS, status)
            .commit()
        VoiceRecordingWidgetProvider.updateAll(this)
    }

    private fun inboxDirectory() = File(filesDir, inboxName)

    private fun finishForegroundIfIdle() {
        if (uiRecordingActive || widgetSession != null) return
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun ensureForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                notificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(notificationId, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                channelId,
                getString(R.string.recording_notification_title),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = getString(R.string.recording_notification_text)
                setShowBadge(false)
            },
        )
    }

    private fun buildUiNotification(): Notification = notificationBuilder()
        .setContentText(getString(R.string.recording_notification_text))
        .build()

    private fun buildWidgetNotification(): Notification {
        val stopIntent = Intent(this, RecordingForegroundService::class.java).apply {
            action = ACTION_WIDGET_STOP
        }
        val pendingStop = PendingIntent.getService(
            this,
            1402,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return notificationBuilder()
            .setContentText(getString(R.string.recording_notification_text))
            .addAction(
                Notification.Action.Builder(
                    null,
                    getString(R.string.recording_notification_stop),
                    pendingStop,
                ).build(),
            )
            .build()
    }

    private fun notificationBuilder(): Notification.Builder {
        val openApp = packageManager.getLaunchIntentForPackage(packageName)
        val pendingOpen = PendingIntent.getActivity(
            this,
            0,
            openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.recording_notification_title))
            .setContentIntent(pendingOpen)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
    }
}
