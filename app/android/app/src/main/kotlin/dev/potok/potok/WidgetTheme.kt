package dev.potok.potok

import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.widget.RemoteViews

data class WidgetThemePalette(
    val background: Int,
    val soft: Int,
    val accentBackground: Int,
    val text: Int,
    val muted: Int,
    val accent: Int,
    val accentText: Int,
    val backgroundColor: Int,
    val softColor: Int,
)

enum class WidgetColorRole { BACKGROUND, SOFT, ACCENT, TEXT, MUTED, ACCENT_TEXT }

object WidgetTheme {
    private val allowed = setOf("studio", "studio-night", "paper", "terminal")

    fun write(
        context: Context,
        mode: String?,
        fixed: String?,
        light: String?,
        dark: String?,
    ) {
        context.getSharedPreferences(LaunchActions.WIDGET_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(LaunchActions.WIDGET_THEME_MODE, if (mode == "system") "system" else "fixed")
            .putString(LaunchActions.WIDGET_THEME_FIXED, valid(fixed, "studio"))
            .putString(LaunchActions.WIDGET_THEME_LIGHT, valid(light, "studio"))
            .putString(LaunchActions.WIDGET_THEME_DARK, valid(dark, "studio-night"))
            .apply()
    }

    fun current(context: Context): WidgetThemePalette {
        val preferences = context.getSharedPreferences(
            LaunchActions.WIDGET_PREFS,
            Context.MODE_PRIVATE,
        )
        val id = if (preferences.getString(LaunchActions.WIDGET_THEME_MODE, "fixed") == "system") {
            val night = context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
            preferences.getString(
                if (night) LaunchActions.WIDGET_THEME_DARK else LaunchActions.WIDGET_THEME_LIGHT,
                if (night) "studio-night" else "studio",
            )
        } else {
            preferences.getString(LaunchActions.WIDGET_THEME_FIXED, "studio")
        }
        return palette(valid(id, "studio"))
    }

    fun applyBackground(
        context: Context,
        views: RemoteViews,
        viewId: Int,
        drawable: Int,
        role: WidgetColorRole,
    ) {
        views.setInt(viewId, "setBackgroundResource", drawable)
        val pair = systemPair(context) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorStateList(
                viewId,
                "setBackgroundTintList",
                ColorStateList.valueOf(color(pair.first, role)),
                ColorStateList.valueOf(color(pair.second, role)),
            )
        }
    }

    fun applyTextColor(
        context: Context,
        views: RemoteViews,
        viewId: Int,
        role: WidgetColorRole,
    ) {
        val current = current(context)
        val pair = systemPair(context)
        if (pair != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorInt(viewId, "setTextColor", color(pair.first, role), color(pair.second, role))
        } else {
            views.setTextColor(viewId, color(current, role))
        }
    }

    fun applyIconColor(
        context: Context,
        views: RemoteViews,
        viewId: Int,
        role: WidgetColorRole,
    ) {
        val current = current(context)
        val pair = systemPair(context)
        if (pair != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorInt(viewId, "setColorFilter", color(pair.first, role), color(pair.second, role))
        } else {
            views.setInt(viewId, "setColorFilter", color(current, role))
        }
    }

    private fun valid(value: String?, fallback: String): String =
        value?.takeIf(allowed::contains) ?: fallback

    private fun systemPair(context: Context): Pair<WidgetThemePalette, WidgetThemePalette>? {
        val preferences = context.getSharedPreferences(
            LaunchActions.WIDGET_PREFS,
            Context.MODE_PRIVATE,
        )
        if (preferences.getString(LaunchActions.WIDGET_THEME_MODE, "fixed") != "system") {
            return null
        }
        val light = valid(
            preferences.getString(LaunchActions.WIDGET_THEME_LIGHT, "studio"),
            "studio",
        )
        val dark = valid(
            preferences.getString(LaunchActions.WIDGET_THEME_DARK, "studio-night"),
            "studio-night",
        )
        return palette(light) to palette(dark)
    }

    private fun color(palette: WidgetThemePalette, role: WidgetColorRole): Int = when (role) {
        WidgetColorRole.BACKGROUND -> palette.backgroundColor
        WidgetColorRole.SOFT -> palette.softColor
        WidgetColorRole.ACCENT -> palette.accent
        WidgetColorRole.TEXT -> palette.text
        WidgetColorRole.MUTED -> palette.muted
        WidgetColorRole.ACCENT_TEXT -> palette.accentText
    }

    private fun palette(id: String): WidgetThemePalette = when (id) {
        "studio-night" -> WidgetThemePalette(
            R.drawable.widget_background_night,
            R.drawable.widget_soft_night,
            R.drawable.widget_accent_night,
            Color.rgb(237, 242, 250),
            Color.rgb(155, 169, 188),
            Color.rgb(140, 167, 255),
            Color.rgb(16, 21, 34),
            Color.rgb(23, 29, 39),
            Color.rgb(29, 37, 49),
        )
        "paper" -> WidgetThemePalette(
            R.drawable.widget_background_paper,
            R.drawable.widget_soft_paper,
            R.drawable.widget_accent_paper,
            Color.rgb(48, 43, 38),
            Color.rgb(117, 107, 97),
            Color.rgb(155, 75, 47),
            Color.WHITE,
            Color.rgb(255, 253, 247),
            Color.rgb(248, 243, 232),
        )
        "terminal" -> WidgetThemePalette(
            R.drawable.widget_background_terminal,
            R.drawable.widget_soft_terminal,
            R.drawable.widget_accent_terminal,
            Color.rgb(200, 247, 220),
            Color.rgb(119, 169, 139),
            Color.rgb(66, 231, 136),
            Color.rgb(4, 20, 10),
            Color.rgb(11, 23, 19),
            Color.rgb(15, 32, 26),
        )
        else -> WidgetThemePalette(
            R.drawable.widget_background,
            R.drawable.widget_list_item_background,
            R.drawable.widget_audio_button,
            Color.rgb(24, 33, 47),
            Color.rgb(100, 112, 132),
            Color.rgb(52, 87, 213),
            Color.WHITE,
            Color.WHITE,
            Color.rgb(245, 247, 250),
        )
    }
}
