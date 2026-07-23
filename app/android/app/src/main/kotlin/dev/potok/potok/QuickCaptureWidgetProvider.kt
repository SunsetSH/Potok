package dev.potok.potok

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class QuickCaptureWidgetProvider : AppWidgetProvider() {
    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, QuickCaptureWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                QuickCaptureWidgetProvider().onUpdate(context, manager, ids)
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val palette = WidgetTheme.current(context)
        appWidgetIds.forEach { appWidgetId ->
            val preferences = context.getSharedPreferences(
                LaunchActions.WIDGET_PREFS,
                Context.MODE_PRIVATE,
            )
            val projectId = preferences.getString(LaunchActions.WIDGET_PROJECT_ID, null)
            val views = RemoteViews(context.packageName, R.layout.quick_capture_widget)
            WidgetTheme.applyBackground(
                context, views, R.id.widget_root, palette.background, WidgetColorRole.BACKGROUND,
                padding = WidgetPadding(10),
            )
            WidgetTheme.applyBackground(
                context, views, R.id.widget_text, palette.soft, WidgetColorRole.SOFT,
            )
            WidgetTheme.applyBackground(
                context, views, R.id.widget_audio, palette.accentBackground, WidgetColorRole.ACCENT,
            )
            WidgetTheme.applyTextColor(context, views, R.id.widget_text_label, WidgetColorRole.ACCENT)
            WidgetTheme.applyTextColor(context, views, R.id.widget_audio_label, WidgetColorRole.ACCENT_TEXT)
            WidgetTheme.applyIconColor(context, views, R.id.widget_text_icon, WidgetColorRole.ACCENT)
            WidgetTheme.applyIconColor(context, views, R.id.widget_audio_icon, WidgetColorRole.ACCENT_TEXT)
            views.setOnClickPendingIntent(
                R.id.widget_text,
                captureIntent(context, LaunchActions.NEW_TEXT, appWidgetId * 2, projectId),
            )
            views.setOnClickPendingIntent(
                R.id.widget_audio,
                captureIntent(context, LaunchActions.NEW_AUDIO, appWidgetId * 2 + 1, projectId),
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun captureIntent(
        context: Context,
        action: String,
        requestCode: Int,
        projectId: String?,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = action
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (projectId != null) putExtra(LaunchActions.EXTRA_PROJECT_ID, projectId)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
