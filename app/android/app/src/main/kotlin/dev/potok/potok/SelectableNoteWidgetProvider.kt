package dev.potok.potok

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.widget.RemoteViews

/**
 * Настраиваемый виджет: показывает конкретную выбранную заметку либо последнюю
 * заметку выбранного проекта. Выбор делается в [SelectableNoteConfigActivity]
 * при размещении и хранится по appWidgetId.
 */
class SelectableNoteWidgetProvider : AppWidgetProvider() {
    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, SelectableNoteWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) SelectableNoteWidgetProvider().onUpdate(context, manager, ids)
        }

        fun render(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val selection = WidgetData.selection(context, appWidgetId)
            val note = when (selection?.mode) {
                WidgetSelection.MODE_LATEST -> WidgetData.latestNote(context)
                WidgetSelection.MODE_FAVORITE -> WidgetData.latestFavorite(context)
                WidgetSelection.MODE_IN_WORK -> WidgetData.latestInWork(context)
                WidgetSelection.MODE_NOTE ->
                    WidgetData.noteById(context, selection.id) ?: WidgetData.latestNote(context)
                WidgetSelection.MODE_PROJECT -> WidgetData.latestInProject(context, selection.id)
                // Старые экземпляры могли быть добавлены, пока сломанный
                // MethodChannel оставлял конфигуратор без данных. После
                // обновления они должны ожить без удаления с рабочего стола.
                else -> WidgetData.latestNote(context)
            }
            val views = RemoteViews(context.packageName, R.layout.note_card_widget)
            NoteCardRenderer.render(context, views, note, appWidgetId)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { WidgetData.clearSelection(context, it) }
    }

}
