package dev.potok.potok

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.view.View
import android.widget.RemoteViews

/** Компактный список последних заметок. Тап по строке — открыть заметку. */
class NoteListWidgetProvider : AppWidgetProvider() {
    companion object {
        private const val maxVisibleNotes = 4

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, NoteListWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) NoteListWidgetProvider().onUpdate(context, manager, ids)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.note_list_widget)
            val palette = WidgetTheme.current(context)
            WidgetTheme.applyBackground(
                context, views, R.id.note_list_root, palette.background, WidgetColorRole.BACKGROUND,
                padding = WidgetPadding(10),
            )
            WidgetTheme.applyTextColor(context, views, R.id.note_list_title, WidgetColorRole.TEXT)
            WidgetTheme.applyTextColor(context, views, R.id.note_list_empty, WidgetColorRole.MUTED)
            WidgetTheme.applyIconColor(context, views, R.id.note_list_icon, WidgetColorRole.ACCENT)
            val notes = WidgetData.notes(context).take(maxVisibleNotes)
            views.removeAllViews(R.id.note_list_container)
            views.setViewVisibility(
                R.id.note_list_empty,
                if (notes.isEmpty()) View.VISIBLE else View.GONE,
            )
            notes.forEachIndexed { index, note ->
                val row = RemoteViews(context.packageName, R.layout.note_list_item)
                renderRow(context, row, note, appWidgetId * 10 + index, palette)
                views.addView(R.id.note_list_container, row)
            }
            // Тап по заголовку — открыть приложение (создать заметку).
            views.setOnClickPendingIntent(
                R.id.note_list_header,
                WidgetData.openAppIntent(context, appWidgetId),
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun renderRow(
        context: Context,
        views: RemoteViews,
        note: WidgetNote,
        requestCode: Int,
        palette: WidgetThemePalette,
    ) {
        WidgetTheme.applyBackground(
            context, views, R.id.list_item_root, palette.soft, WidgetColorRole.SOFT,
            padding = WidgetPadding(horizontalDp = 12, verticalDp = 10),
        )
        WidgetTheme.applyTextColor(context, views, R.id.list_item_title, WidgetColorRole.TEXT)
        WidgetTheme.applyTextColor(context, views, R.id.list_item_snippet, WidgetColorRole.MUTED)
        WidgetTheme.applyTextColor(context, views, R.id.list_item_project, WidgetColorRole.ACCENT)
        views.setTextViewText(R.id.list_item_title, note.title)
        views.setViewVisibility(
            R.id.list_item_snippet,
            if (note.snippet.isEmpty()) View.GONE else View.VISIBLE,
        )
        if (note.snippet.isNotEmpty()) {
            views.setTextViewText(R.id.list_item_snippet, note.snippet)
        }
        views.setViewVisibility(
            R.id.list_item_project,
            if (note.project.isEmpty()) View.GONE else View.VISIBLE,
        )
        if (note.project.isNotEmpty()) {
            views.setTextViewText(R.id.list_item_project, note.project)
        }
        views.setOnClickPendingIntent(
            R.id.list_item_root,
            WidgetData.openNoteIntent(context, requestCode, note.id),
        )
    }
}
