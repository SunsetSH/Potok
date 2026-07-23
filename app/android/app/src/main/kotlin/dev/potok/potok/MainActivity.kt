package dev.potok.potok

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.StatFs
import android.util.Log
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {
    companion object {
        private const val launchChannelName = "dev.potok/launch_intents"
        private const val maxPendingLaunches = 8
        private const val maxSharedTextCodePoints = 100_000
        private val projectIdPattern = Regex("^[A-Za-z0-9_-]{1,128}$")
    }

    private val pendingLaunches = ArrayDeque<Map<String, Any?>>()
    private lateinit var launchChannel: MethodChannel
    private var initialIntentEnqueued = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.potok/recording",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFreeBytes" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("invalid_argument", "path is required", null)
                    } else {
                        try {
                            result.success(StatFs(path).availableBytes)
                        } catch (error: IllegalArgumentException) {
                            result.error("storage_unavailable", "managed storage unavailable", null)
                        }
                    }
                }
                "setRecordingActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    try {
                        setRecordingActive(active)
                        result.success(null)
                    } catch (error: RuntimeException) {
                        result.error("recording_service_failed", error.javaClass.simpleName, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        launchChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            launchChannelName,
        )
        launchChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeNext" -> result.success(pendingLaunches.pollFirst())
                "setWidgetProject" -> {
                    val id = call.argument<String>("id")?.takeIf(projectIdPattern::matches)
                    val name = call.argument<String>("name")?.trim()?.take(120)
                        ?.takeIf(String::isNotEmpty)
                    val preferences = getSharedPreferences(LaunchActions.WIDGET_PREFS, MODE_PRIVATE)
                    preferences.edit().apply {
                        if (id == null || name == null) {
                            remove(LaunchActions.WIDGET_PROJECT_ID)
                            remove(LaunchActions.WIDGET_PROJECT_NAME)
                        } else {
                            putString(LaunchActions.WIDGET_PROJECT_ID, id)
                            putString(LaunchActions.WIDGET_PROJECT_NAME, name)
                        }
                    }.apply()
                    QuickCaptureWidgetProvider.updateAll(this)
                    result.success(null)
                }
                "setWidgetData" -> {
                    val committed = WidgetData.writeData(
                        this,
                        call.argument<String>("notes"),
                        call.argument<String>("projects"),
                    )
                    if (!committed) {
                        result.error("widget_cache_write_failed", "Widget cache unavailable", null)
                        return@setMethodCallHandler
                    }
                    Log.i(
                        "PotokWidgets",
                        "cache updated notes=${WidgetData.notes(this).size} " +
                            "projects=${WidgetData.projects(this).size}",
                    )
                    refreshAllNoteWidgets()
                    result.success(null)
                }
                "setWidgetTheme" -> {
                    WidgetTheme.write(
                        this,
                        call.argument<String>("mode"),
                        call.argument<String>("fixed"),
                        call.argument<String>("light"),
                        call.argument<String>("dark"),
                    )
                    refreshAllNoteWidgets()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        if (!initialIntentEnqueued) {
            initialIntentEnqueued = true
            enqueueLaunch(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (enqueueLaunch(intent) && ::launchChannel.isInitialized) {
            launchChannel.invokeMethod("launchIntentAvailable", null)
        }
    }

    private fun enqueueLaunch(source: Intent?): Boolean {
        if (source == null) return false
        val request = when (source.action) {
            LaunchActions.NEW_TEXT -> launchRequest("text", source)
            LaunchActions.NEW_AUDIO -> launchRequest("audio", source)
            LaunchActions.OPEN_NOTE -> openNoteRequest(source)
            Intent.ACTION_SEND -> shareRequest(source)
            else -> null
        } ?: return false
        if (pendingLaunches.size >= maxPendingLaunches) pendingLaunches.removeFirst()
        pendingLaunches.addLast(request)
        return true
    }

    private fun openNoteRequest(source: Intent): Map<String, Any?>? {
        val noteId = source.getStringExtra(LaunchActions.EXTRA_NOTE_ID)
            ?.takeIf(projectIdPattern::matches) ?: return null
        return mapOf("kind" to "openNote", "noteId" to noteId)
    }

    private fun refreshAllNoteWidgets() {
        QuickCaptureWidgetProvider.updateAll(this)
        RecentNoteWidgetProvider.updateAll(this)
        SelectableNoteWidgetProvider.updateAll(this)
        NoteListWidgetProvider.updateAll(this)
    }

    private fun launchRequest(kind: String, source: Intent): Map<String, Any?> {
        val projectId = source.getStringExtra(LaunchActions.EXTRA_PROJECT_ID)
            ?.takeIf(projectIdPattern::matches)
        return buildMap {
            put("kind", kind)
            if (projectId != null) put("projectId", projectId)
        }
    }

    private fun shareRequest(source: Intent): Map<String, Any?>? {
        if (source.type?.startsWith("text/") != true) return null
        val subject = source.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()?.trim().orEmpty()
        val body = source.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val combined = listOf(subject, body).filter(String::isNotEmpty).distinct().joinToString("\n\n")
        if (combined.isEmpty()) return null
        return mapOf("kind" to "share", "text" to boundCodePoints(combined))
    }

    private fun boundCodePoints(value: String): String {
        val count = value.codePointCount(0, value.length)
        if (count <= maxSharedTextCodePoints) return value
        val end = value.offsetByCodePoints(0, maxSharedTextCodePoints)
        return value.substring(0, end)
    }

    private fun setRecordingActive(active: Boolean) {
        val service = Intent(this, RecordingForegroundService::class.java)
        if (active) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 401)
            }
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            ContextCompat.startForegroundService(this, service)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            stopService(service)
        }
    }
}
