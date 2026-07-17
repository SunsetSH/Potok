package dev.potok.potok

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.StatFs
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
