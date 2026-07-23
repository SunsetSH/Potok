package dev.potok.potok

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.ListView
import android.widget.RadioGroup
import android.widget.TextView
import android.text.Editable
import android.text.TextWatcher

/**
 * Настройка виджета «Заметка на выбор»: пользователь выбирает конкретную
 * заметку или проект (тогда показывается последняя заметка этого проекта).
 * Данные берутся из кэша [WidgetData]; БД приложения не открывается.
 */
class SelectableNoteConfigActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var mode = WidgetSelection.MODE_LATEST

    private lateinit var list: ListView
    private lateinit var emptyLabel: TextView
    private lateinit var search: EditText
    private lateinit var apply: Button
    private var notes: List<WidgetNote> = emptyList()
    private var projects: List<WidgetProject> = emptyList()
    private var visibleNotes: List<WidgetNote> = emptyList()
    private var visibleProjects: List<WidgetProject> = emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Если пользователь выйдет, не завершив выбор — виджет не добавляется.
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(R.layout.widget_config_activity)
        list = findViewById(R.id.config_list)
        emptyLabel = findViewById(R.id.config_empty)
        search = findViewById(R.id.config_search)
        apply = findViewById(R.id.config_apply)
        notes = WidgetData.notes(this)
        projects = WidgetData.projects(this)

        findViewById<RadioGroup>(R.id.config_mode).setOnCheckedChangeListener { _, checkedId ->
            mode = when (checkedId) {
                R.id.config_mode_favorite -> WidgetSelection.MODE_FAVORITE
                R.id.config_mode_in_work -> WidgetSelection.MODE_IN_WORK
                R.id.config_mode_note -> WidgetSelection.MODE_NOTE
                R.id.config_mode_project -> WidgetSelection.MODE_PROJECT
                else -> WidgetSelection.MODE_LATEST
            }
            search.setText("")
            populate()
        }
        search.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(value: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(value: CharSequence?, start: Int, before: Int, count: Int) {
                populate(value?.toString().orEmpty())
            }
            override fun afterTextChanged(value: Editable?) {}
        })
        list.onItemClickListener = AdapterView.OnItemClickListener { _, _, position, _ ->
            onPicked(position)
        }
        apply.setOnClickListener { saveAndFinish(WidgetSelection(mode)) }
        populate()
    }

    private fun populate(query: String = search.text?.toString().orEmpty()) {
        val needsList = mode == WidgetSelection.MODE_NOTE || mode == WidgetSelection.MODE_PROJECT
        search.visibility = if (needsList) View.VISIBLE else View.GONE
        list.visibility = if (needsList) View.VISIBLE else View.GONE
        apply.visibility = if (needsList) View.GONE else View.VISIBLE

        val needle = query.trim().lowercase()
        visibleProjects = projects.filter { project ->
            needle.isEmpty() || project.name.lowercase().contains(needle)
        }
        visibleNotes = notes.filter { note ->
            needle.isEmpty() || listOf(note.title, note.snippet, note.project)
                .any { it.lowercase().contains(needle) }
        }
        val items = when (mode) {
            WidgetSelection.MODE_PROJECT -> visibleProjects.map { it.name }
            WidgetSelection.MODE_NOTE -> visibleNotes.map { note ->
                if (note.project.isEmpty()) note.title else "${note.title}\n${note.project}"
            }
            else -> emptyList()
        }
        list.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_list_item_1,
            items,
        )
        val empty = needsList && items.isEmpty()
        if (needsList) list.visibility = if (empty) View.GONE else View.VISIBLE
        emptyLabel.visibility = if (empty) View.VISIBLE else View.GONE
        emptyLabel.text = if (mode == WidgetSelection.MODE_PROJECT) {
            getString(R.string.widget_config_no_projects)
        } else {
            getString(R.string.widget_config_no_notes)
        }
    }

    private fun onPicked(position: Int) {
        val selection = if (mode == WidgetSelection.MODE_PROJECT) {
            visibleProjects.getOrNull(position)?.let {
                WidgetSelection(WidgetSelection.MODE_PROJECT, it.id)
            }
        } else {
            visibleNotes.getOrNull(position)?.let {
                WidgetSelection(WidgetSelection.MODE_NOTE, it.id)
            }
        } ?: return

        saveAndFinish(selection)
    }

    private fun saveAndFinish(selection: WidgetSelection) {
        WidgetData.saveSelection(this, appWidgetId, selection)
        SelectableNoteWidgetProvider.render(
            this,
            AppWidgetManager.getInstance(this),
            appWidgetId,
        )
        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
        )
        finish()
    }
}
