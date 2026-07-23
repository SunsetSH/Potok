package dev.potok.potok

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

/** Компактная запись заметки для виджета (кэш в SharedPreferences). */
data class WidgetNote(
    val id: String,
    val title: String,
    val snippet: String,
    val project: String,
    val projectId: String,
    val favorite: Boolean,
    val status: String,
)

data class WidgetProject(val id: String, val name: String)

/** Выбор конфигурируемого виджета: динамическая подборка либо закреплённая заметка. */
data class WidgetSelection(val mode: String, val id: String = "") {
    companion object {
        const val MODE_LATEST = "latest"
        const val MODE_FAVORITE = "favorite"
        const val MODE_IN_WORK = "in_work"
        const val MODE_NOTE = "note"
        const val MODE_PROJECT = "project"
    }
}

/**
 * Единая точка чтения кэша заметок/проектов, который пушит Flutter. Виджеты и
 * конфиг-активити никогда не открывают БД приложения — только этот кэш.
 */
object WidgetData {
    private fun prefs(context: Context) =
        context.getSharedPreferences(LaunchActions.WIDGET_PREFS, Context.MODE_PRIVATE)

    fun notes(context: Context): List<WidgetNote> {
        val raw = prefs(context).getString(LaunchActions.WIDGET_NOTES, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val obj = array.optJSONObject(index) ?: return@mapNotNull null
                val id = obj.optString("id")
                if (id.isEmpty()) return@mapNotNull null
                WidgetNote(
                    id = id,
                    title = obj.optString("title"),
                    snippet = obj.optString("snippet"),
                    project = obj.optString("project"),
                    projectId = obj.optString("projectId"),
                    favorite = obj.optBoolean("favorite"),
                    status = obj.optString("status"),
                )
            }
        } catch (error: Exception) {
            emptyList()
        }
    }

    fun projects(context: Context): List<WidgetProject> {
        val raw = prefs(context).getString(LaunchActions.WIDGET_PROJECTS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val obj = array.optJSONObject(index) ?: return@mapNotNull null
                val id = obj.optString("id")
                val name = obj.optString("name")
                if (id.isEmpty() || name.isEmpty()) null else WidgetProject(id, name)
            }
        } catch (error: Exception) {
            emptyList()
        }
    }

    fun latestNote(context: Context): WidgetNote? = notes(context).firstOrNull()

    fun latestFavorite(context: Context): WidgetNote? =
        notes(context).firstOrNull { it.favorite }

    fun latestInWork(context: Context): WidgetNote? =
        notes(context).firstOrNull { it.status == WidgetSelection.MODE_IN_WORK }

    fun noteById(context: Context, id: String): WidgetNote? =
        notes(context).firstOrNull { it.id == id }

    /** Заметки отсортированы новейшими сверху, поэтому first = последняя. */
    fun latestInProject(context: Context, projectId: String): WidgetNote? =
        notes(context).firstOrNull { it.projectId == projectId }

    fun writeData(context: Context, notesJson: String?, projectsJson: String?): Boolean {
        return prefs(context).edit().apply {
            if (notesJson != null) putString(LaunchActions.WIDGET_NOTES, notesJson)
            if (projectsJson != null) putString(LaunchActions.WIDGET_PROJECTS, projectsJson)
        }.commit()
    }

    fun selection(context: Context, appWidgetId: Int): WidgetSelection? {
        val raw = prefs(context)
            .getString(LaunchActions.WIDGET_SELECTION_PREFIX + appWidgetId, null)
            ?: return null
        return try {
            val obj = JSONObject(raw)
            val mode = obj.optString("mode")
            val id = obj.optString("id")
            if (mode.isEmpty()) null else WidgetSelection(mode, id)
        } catch (error: Exception) {
            null
        }
    }

    fun saveSelection(context: Context, appWidgetId: Int, selection: WidgetSelection) {
        val obj = JSONObject()
            .put("mode", selection.mode)
            .put("id", selection.id)
        prefs(context).edit()
            .putString(LaunchActions.WIDGET_SELECTION_PREFIX + appWidgetId, obj.toString())
            .apply()
    }

    fun clearSelection(context: Context, appWidgetId: Int) {
        prefs(context).edit()
            .remove(LaunchActions.WIDGET_SELECTION_PREFIX + appWidgetId)
            .apply()
    }

    /** PendingIntent открытия конкретной заметки (для одиночных виджетов). */
    fun openNoteIntent(context: Context, requestCode: Int, noteId: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = LaunchActions.OPEN_NOTE
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(LaunchActions.EXTRA_NOTE_ID, noteId)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** PendingIntent запуска приложения (когда показывать нечего). */
    fun openAppIntent(context: Context, requestCode: Int): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
