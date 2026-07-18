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
        appWidgetIds.forEach { appWidgetId ->
            val preferences = context.getSharedPreferences(
                LaunchActions.WIDGET_PREFS,
                Context.MODE_PRIVATE,
            )
            val projectId = preferences.getString(LaunchActions.WIDGET_PROJECT_ID, null)
            val views = RemoteViews(context.packageName, R.layout.quick_capture_widget)
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
