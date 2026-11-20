package modus_viewer

// The settings: gui_toolkit's page of the preferences (gt:prefs_page), in place of the form or of the screen. The gear
// of the title bar, of the bar or of the form opens it; the arrow or Escape goes back. Each change is applied at once:
// the standard settings by prefs_page.standard_watch, the viewer's by settings_changed. The writer of the preferences
// saves the file off the window's thread (the loop of main).

import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"

settings_toggle :: proc(app: ^App) {
	app.settings_open = !app.settings_open
	if app.settings_open {
		prefs_page.focus_search(&app.settings_page)
	}
}

// The General page: where the viewer says what it did, and its language.
@(private = "file", rodata)
GENERAL_NAMES := [?]string{prefs_page.MESSAGES_PREF, prefs_page.LANGUAGE_PREF}

// The pages, their order and their icons: each a group of the registry. The titles are English: the page translates
// them where it shows them.
@(private = "file")
SETTINGS_PAGES := [?]prefs_page.Page_Info {
	{category = "general", title = i18n.later("General"), icon = lucide.SETTINGS, names = GENERAL_NAMES[:]},
	{category = "viewer", title = i18n.later("Viewer"), icon = lucide.MONITOR},
	{category = "appearance", title = i18n.later("Appearance"), icon = lucide.PALETTE},
	{category = "window", title = i18n.later("Window"), icon = lucide.APP_WINDOW},
	{category = "input", title = i18n.later("Input"), icon = lucide.MOUSE},
	{category = "keys", title = i18n.later("Keys"), icon = lucide.KEYBOARD},
	{category = "timing", title = i18n.later("Delays and menus"), icon = lucide.TIMER},
	{category = "scrolling", title = i18n.later("Scrolling"), icon = lucide.MOUSE_POINTER},
	{category = "update", title = i18n.later("Updates"), icon = lucide.DOWNLOAD},
	{category = "rendering", title = i18n.later("Rendering"), icon = lucide.MONITOR_COG},
}

// What the viewer has to say under a line: a title bar that the desktop does not draw.
@(private = "file")
settings_problem :: proc(user: rawptr, name: string) -> string {
	app := (^App)(user)
	if name == prefs_page.SYSTEM_TITLE_PREF && app.settings.system_title && !platform.system_title_available(app.main.win) {
		return i18n.tr("This desktop draws no title bar for the window of the viewer: the viewer keeps its own.")
	}
	return ""
}

// The page, as large as what is left under the title bar.
settings_build :: proc(app: ^App) {
	ui.next({width = ui.fill(), height = ui.fill()})
	prefs_page.build(&app.settings_page, &app.prefs, settings_options(app))
}

settings_options :: proc(app: ^App) -> prefs_page.Page_Options {
	return {
		user = app, changed = settings_changed, problem = settings_problem,
		updater = app.updates.updater, restart = proc(user: rawptr) { app_restart((^App)(user)) },
		pages = SETTINGS_PAGES[:], icon_font = ui.lucide_icons(), search_icon = lucide.SEARCH, reset_icon = lucide.ROTATE_CCW,
		file = app.prefs_path,
		version = APP_TITLE + " " + APP_VERSION,
		themes = ui.THEMES[:], themes_light = app.theme_shown.light,
		diagnostics = prefs_page.diagnostics_of(&app.main),
	}
}

// A preference was set or reset: the viewer's settings read again; the standard ones are applied by standard_watch.
@(private = "file")
settings_changed :: proc(user: rawptr, name: string) {
	app := (^App)(user)
	settings_free(&app.settings)
	app.settings = prefs_read(&app.prefs)
	app.announcer.mode = app.settings.messages
	app.scale_mode = app.settings.scale
	platform.set_integrated_title(app.main.win, !app.settings.system_title)
}
