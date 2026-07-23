package dev.potok.potok

import android.Manifest
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.widget.RemoteViews
import androidx.core.content.ContextCompat

/** One-tap native voice capture; opening Flutter is not required. */
class VoiceRecordingWidgetProvider : AppWidgetProvider() {
    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, VoiceRecordingWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            ids.forEach { render(context, manager, it) }
        }

        private fun render(context: Context, manager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.voice_recording_widget)
            val palette = WidgetTheme.current(context)
            WidgetTheme.applyBackground(
                context,
                views,
                R.id.voice_widget_root,
                palette.background,
                WidgetColorRole.BACKGROUND,
                padding = WidgetPadding(10),
            )
            WidgetTheme.applyBackground(
                context,
                views,
                R.id.voice_widget_button,
                palette.accentBackground,
                WidgetColorRole.ACCENT,
            )
            WidgetTheme.applyTextColor(
                context,
                views,
                R.id.voice_widget_label,
                WidgetColorRole.ACCENT_TEXT,
            )
            WidgetTheme.applyIconColor(
                context,
                views,
                R.id.voice_widget_icon,
                WidgetColorRole.ACCENT_TEXT,
            )

            val permissionGranted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED
            val active = RecordingForegroundService.isWidgetRecording(context)
            val status = RecordingForegroundService.widgetStatus(context)
            when {
                !permissionGranted -> {
                    views.setTextViewText(
                        R.id.voice_widget_label,
                        context.getString(R.string.widget_voice_permission),
                    )
                    views.setImageViewResource(R.id.voice_widget_icon, R.drawable.widget_mic_icon)
                    views.setOnClickPendingIntent(
                        R.id.voice_widget_button,
                        openPermissionFlow(context, appWidgetId),
                    )
                }
                active -> {
                    views.setTextViewText(
                        R.id.voice_widget_label,
                        context.getString(R.string.widget_voice_stop),
                    )
                    views.setImageViewResource(R.id.voice_widget_icon, R.drawable.widget_stop_icon)
                    views.setOnClickPendingIntent(
                        R.id.voice_widget_button,
                        serviceIntent(context, appWidgetId),
                    )
                }
                status == "storage" -> renderIdleError(
                    context,
                    views,
                    R.string.widget_voice_storage,
                    appWidgetId,
                )
                status == "busy" -> renderIdleError(
                    context,
                    views,
                    R.string.widget_voice_busy,
                    appWidgetId,
                )
                status == "device" || status == "error" -> renderIdleError(
                    context,
                    views,
                    R.string.widget_voice_error,
                    appWidgetId,
                )
                else -> {
                    views.setTextViewText(
                        R.id.voice_widget_label,
                        context.getString(R.string.widget_voice_start),
                    )
                    views.setImageViewResource(R.id.voice_widget_icon, R.drawable.widget_mic_icon)
                    views.setOnClickPendingIntent(
                        R.id.voice_widget_button,
                        serviceIntent(context, appWidgetId),
                    )
                }
            }
            manager.updateAppWidget(appWidgetId, views)
        }

        private fun renderIdleError(
            context: Context,
            views: RemoteViews,
            label: Int,
            requestCode: Int,
        ) {
            views.setTextViewText(R.id.voice_widget_label, context.getString(label))
            views.setImageViewResource(R.id.voice_widget_icon, R.drawable.widget_mic_icon)
            views.setOnClickPendingIntent(
                R.id.voice_widget_button,
                serviceIntent(context, requestCode),
            )
        }

        private fun serviceIntent(context: Context, requestCode: Int): PendingIntent {
            val intent = Intent(context, RecordingForegroundService::class.java).apply {
                action = RecordingForegroundService.ACTION_WIDGET_TOGGLE
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(context, requestCode, intent, flags)
            } else {
                PendingIntent.getService(context, requestCode, intent, flags)
            }
        }

        private fun openPermissionFlow(context: Context, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = LaunchActions.NEW_AUDIO
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }
}
