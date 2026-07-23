package dev.potok.potok

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.view.View
import android.widget.RemoteViews

/** Виджет с последней добавленной заметкой. Тап — открыть её. */
class RecentNoteWidgetProvider : AppWidgetProvider() {
    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, RecentNoteWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) RecentNoteWidgetProvider().onUpdate(context, manager, ids)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val note = WidgetData.latestNote(context)
        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.note_card_widget)
            NoteCardRenderer.render(context, views, note, appWidgetId)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

}

/** Общая отрисовка карточки одной заметки для одиночных виджетов. */
object NoteCardRenderer {
    fun render(context: Context, views: RemoteViews, note: WidgetNote?, requestCode: Int) {
        val palette = WidgetTheme.current(context)
        WidgetTheme.applyBackground(
            context, views, R.id.note_card_root, palette.background, WidgetColorRole.BACKGROUND,
        )
        WidgetTheme.applyTextColor(context, views, R.id.note_card_title, WidgetColorRole.TEXT)
        WidgetTheme.applyTextColor(context, views, R.id.note_card_snippet, WidgetColorRole.MUTED)
        WidgetTheme.applyTextColor(context, views, R.id.note_card_empty, WidgetColorRole.MUTED)
        WidgetTheme.applyTextColor(context, views, R.id.note_card_project, WidgetColorRole.ACCENT)
        WidgetTheme.applyBackground(
            context, views, R.id.note_card_project, palette.soft, WidgetColorRole.SOFT,
        )
        if (note == null) {
            views.setViewVisibility(R.id.note_card_content, View.GONE)
            views.setViewVisibility(R.id.note_card_empty, View.VISIBLE)
            views.setOnClickPendingIntent(
                R.id.note_card_root,
                WidgetData.openAppIntent(context, requestCode),
            )
            return
        }
        views.setViewVisibility(R.id.note_card_content, View.VISIBLE)
        views.setViewVisibility(R.id.note_card_empty, View.GONE)
        views.setTextViewText(R.id.note_card_title, note.title)
        if (note.snippet.isEmpty()) {
            views.setViewVisibility(R.id.note_card_snippet, View.GONE)
        } else {
            views.setViewVisibility(R.id.note_card_snippet, View.VISIBLE)
            views.setTextViewText(R.id.note_card_snippet, note.snippet)
        }
        if (note.project.isEmpty()) {
            views.setViewVisibility(R.id.note_card_project, View.GONE)
        } else {
            views.setViewVisibility(R.id.note_card_project, View.VISIBLE)
            views.setTextViewText(R.id.note_card_project, note.project)
        }
        views.setOnClickPendingIntent(
            R.id.note_card_root,
            WidgetData.openNoteIntent(context, requestCode, note.id),
        )
    }
}
