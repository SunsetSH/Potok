package dev.potok.potok

object LaunchActions {
    const val NEW_TEXT = "dev.potok.action.NEW_TEXT_NOTE"
    const val NEW_AUDIO = "dev.potok.action.NEW_AUDIO_NOTE"
    const val OPEN_NOTE = "dev.potok.action.OPEN_NOTE"
    const val EXTRA_PROJECT_ID = "dev.potok.extra.PROJECT_ID"
    const val EXTRA_NOTE_ID = "dev.potok.extra.NOTE_ID"

    const val WIDGET_PREFS = "potok_widget"
    const val WIDGET_PROJECT_ID = "project_id"
    const val WIDGET_PROJECT_NAME = "project_name"

    /** JSON-массив последних заметок: [{id,title,snippet,project,projectId}]. */
    const val WIDGET_NOTES = "notes_json"

    /** JSON-массив проектов: [{id,name}]. */
    const val WIDGET_PROJECTS = "projects_json"
    const val WIDGET_THEME_MODE = "theme_mode"
    const val WIDGET_THEME_FIXED = "theme_fixed"
    const val WIDGET_THEME_LIGHT = "theme_light"
    const val WIDGET_THEME_DARK = "theme_dark"

    /** Префикс ключа выбора конфигурируемого виджета по appWidgetId. */
    const val WIDGET_SELECTION_PREFIX = "selection_"
}
