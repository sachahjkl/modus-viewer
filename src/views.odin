package modus_viewer

// The views of the window (src/md/features/interface.md): the title bar, the settings, the form, the plate of a
// connection that starts or ended, and the screen of the machine with its bar.

import "core:fmt"
import "core:math"
import "core:time"
import crash_bar "gt:crash_bar"
import "gt:draw"
import host "gt:host"
import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:render"
import "gt:ui"
import "layout"

// What the window shows. Derived each frame from what the window holds, never stored.
View_State :: enum u8 {
	Settings,   // The user opened the settings.
	Form,       // No session was asked yet.
	Connecting, // A connection runs, or starts with the viewer, and no whole frame came.
	Screen,     // A whole frame came: the screen of the machine, alone.
	Ended,      // The last connection ended: its sentence, Retry, and Change the address.
}

// The side of the arrow of the pointer of the machine, in logical pixels: the size of the pointer theme of modus.
ARROW_SIZE :: 24
// The width of the plate of a message and of the form, in em.
PLATE_WIDTH_EM :: f32(34)
FORM_WIDTH_EM :: f32(40)
// The height of the title bar, in em: the toolkit's programs have the same.
TITLE_BAR_EM :: f32(2.6)

view_state :: proc(app: ^App) -> View_State {
	switch {
	case app.settings_open:
		return .Settings
	case app.viewer_connection != nil && app.frames > 0 && app.texture != 0:
		return .Screen
	case app.viewer_connection != nil, app.connect_at_start:
		return .Connecting
	case app.has_retry && app.end_sentence != "":
		return .Ended
	}
	return .Form
}

build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	em := ui.font_size()
	state := view_state(app)
	if platform.is_integrated_title(h.win) && !platform.is_fullscreen(h.win) {
		title_bar_build(app, state, em)
	}
	crash_bar.bar(&app.crash_bar, {name = APP_TITLE, version = APP_VERSION, repository = REPOSITORY})
	switch state {
	case .Settings:
		settings_build(app)
	case .Form:
		form_build(app)
	case .Connecting:
		// Before the viewer key arrives, a session that starts with the viewer has no machine name yet.
		title := app.machine_name != "" ? fmt.tprintf(i18n.tr("Connecting to %s"), app.machine_name) : i18n.tr("Connecting")
		message_build(app, title, "", false)
	case .Ended:
		message_build(app, fmt.tprintf(i18n.tr("The session with %s ended"), app.machine_name), app.end_sentence, true)
	case .Screen:
		screen_build(app)
	}
	if app.toast_due != .None {
		words := app.toast_due == .Released ? i18n.tr("Input released — %s to give it back") : i18n.tr("Input given to the machine — %s to take it back")
		ui.announce(&app.announcer, .Info, fmt.tprintf(words, shortcut_words(&app.prefs)), in_window = true)
		app.toast_due = .None
	}
}

// title_bar_build is the window's own title bar (the system's when window.system_title): the name of the machine or of
// the viewer, the update's badge, about, the settings and the window's buttons. Its empty parts move the window.
@(private = "file")
title_bar_build :: proc(app: ^App, state: View_State, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(math.round(em * TITLE_BAR_EM))})
	if ui.title_bar("###titlebar") {
		ui.space(ui.SPACE_3)
		ui.next({width = ui.text_size(), height = ui.pct(1), text_pad = 0})
		name := state == .Screen || state == .Connecting || state == .Ended ? app.machine_name : APP_TITLE
		ui.label(fmt.tprintf("%s###title_name", name))
		ui.spacer(ui.fill())
		if app.updates.updater != nil {
			ui.next({height = ui.px(math.round(em * 1.9))})
			if prefs_page.update_badge(app.updates.updater, proc(user: rawptr) { app_restart((^App)(user)) }, app) != nil {
				ui.space(ui.CONTROL_GAP)
			}
		}
		if title_button("###about", lucide.INFO, i18n.tr("About"), em) {
			about(app)
		}
		ui.space(ui.TOOL_GAP)
		if state == .Settings {
			if title_button("###back", lucide.ARROW_LEFT, i18n.tr("Back"), em) {
				app.settings_open = false
			}
		} else if title_button("###settings", lucide.SETTINGS, i18n.tr("Settings"), em) {
			settings_toggle(app)
		}
		ui.space(ui.CONTROL_GAP)
		ui.window_buttons()
	}
}

// A small button of the title bar: a Lucide icon, its tooltip says what it does.
@(private = "file")
title_button :: proc(id, glyph, tip: string, em: f32) -> bool {
	side := math.round(em * 2)
	ui.next({width = ui.px(side), height = ui.px(side), radius = math.round(em * 0.4)})
	return ui.button(id, icon = glyph, o = {tip = tip, icon_font = ui.lucide_icons(), quiet = true}).clicked
}

// plate_begin opens a plate of the finish in the middle of the room: the form and the messages are dialogs on the
// background of the window.
@(private = "file", deferred_none = plate_end)
plate_begin :: proc(id: string, width_em: f32) -> bool {
	em := ui.font_size()
	ui.next({width = ui.fill(), height = ui.fill()})
	_ = ui.column(.Center)
	ui.spacer(ui.fill())
	ui.next({width = ui.px(math.round(em * width_em)), height = ui.children_sum(), axis = .Y, radius = math.round(em * ui.shape_of(.Dialog))})
	plate := ui.build_box({.Plate}, id)
	ui.push_parent(plate)
	ui.space(ui.SPACE_4)
	ui.next({width = ui.fill(), height = ui.children_sum()})
	_ = ui.row()
	ui.space(ui.SPACE_4)
	ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
	_ = ui.column()
	return true
}

@(private = "file")
plate_end :: proc() {
	ui.pop_parent() // the inner column
	ui.space(ui.SPACE_4)
	ui.pop_parent() // the row of the margins
	ui.space(ui.SPACE_4)
	ui.pop_parent() // the plate
	ui.spacer(ui.fill())
	ui.pop_parent() // the outer column
}

form_build :: proc(app: ^App) {
	em := ui.font_size()
	if plate_begin("###form", FORM_WIDTH_EM) {
		ui.next({width = ui.fill()})
		ui.label(fmt.tprintf("%s###allow_title", i18n.tr("Allow this viewer in a console of the machine:")))
		ui.next({width = ui.fill()})
		ui.line_edit("###allow", &app.allow_line, {kind = .Read_Only, placeholder = i18n.tr(VIEWER_KEY_ORIGIN_SENTENCES[.Loading])})
		if sentence := VIEWER_KEY_ORIGIN_SENTENCES[app.key.origin]; sentence != "" && app.key.origin != .Loading {
			ui.paragraph(fmt.tprintf("%s###origin", i18n.tr(sentence)))
		}
		recent := recent_machines(&app.prefs)
		if len(recent) > 0 {
			ui.space(ui.SPACE_4)
			if ui.tags("weak") {
				ui.label(fmt.tprintf("%s###recent_title", i18n.tr("Recent machines")))
			}
			for machine, index in recent {
				ui.next({width = ui.fill()})
				words := fmt.tprintf(i18n.tr("machine %s, at %s"), machine.machine_key[:MACHINE_NAME_BYTES * 2], machine.address)
				if ui.button(fmt.tprintf("recent_%d", index), words, o = {face = ui.Button_Face.Ghost, left = true}).clicked {
					form_recent(app, machine)
				}
			}
		}
		ui.space(ui.SPACE_4)
		ui.label(fmt.tprintf("%s###address_title", i18n.tr("Address of the machine")))
		ui.next({width = ui.fill()})
		ui.line_edit("###address", &app.address, {placeholder = "host:7101"})
		ui.space(ui.SPACE_3)
		ui.label(fmt.tprintf("%s###machine_key_title", i18n.tr("Machine key")))
		ui.next({width = ui.fill()})
		ui.line_edit("###machine_key", &app.machine_key, {placeholder = i18n.tr("the public key that remote_display writes on the log of the machine")})
		ui.space(ui.SPACE_3)
		if ui.toggle("input", i18n.tr("Send my keys and my pointer"), &app.input) {
			allow_line_update(app)
		}
		if app.form_problem != .None {
			ui.space(ui.SPACE_3)
			if ui.tags("bad") {
				ui.paragraph(fmt.tprintf("%s###form_problem", i18n.tr(FORM_PROBLEM_SENTENCES[app.form_problem])))
			}
		}
		ui.space(ui.SPACE_4)
		ui.next({width = ui.fill(), height = ui.children_sum()})
		if ui.row(.Center, id = "###form_acts") {
			program_acts(app, em)
			ui.spacer(ui.fill())
			if ui.button("connect", i18n.tr("Connect"), o = {intent = .Primary}).clicked {
				form_connect(app)
			}
		}
	}
}

// message_build is the plate of a connection that starts or ended: a title, a sentence and, after an end, Retry and
// Change the address.
@(private = "file")
message_build :: proc(app: ^App, title, sentence: string, ended: bool) {
	em := ui.font_size()
	if plate_begin("###message", PLATE_WIDTH_EM) {
		ui.next({width = ui.fill(), font_size = math.round(em * 1.2)})
		ui.label(fmt.tprintf("%s###message_title", title))
		if sentence != "" {
			ui.space(ui.SPACE_3)
			ui.paragraph(fmt.tprintf("%s###message_sentence", sentence))
		}
		ui.space(ui.SPACE_4)
		ui.next({width = ui.fill(), height = ui.children_sum()})
		if ui.row(.Center, id = "###message_acts") {
			program_acts(app, em)
			ui.spacer(ui.fill())
			if ended {
				if ui.button("change_address", i18n.tr("Change the address")).clicked {
					session_forget(app)
				}
				ui.space(ui.CONTROL_GAP)
				if ui.button("retry", i18n.tr("Retry"), o = {intent = .Primary}).clicked {
					session_retry(app)
				}
			} else if ui.button("cancel", i18n.tr("Cancel")).clicked {
				connection_end_asked(app)
			}
		}
	}
}

// The acts of the program, for a window with the system's title bar: the settings and about.
@(private = "file")
program_acts :: proc(app: ^App, em: f32) {
	if platform.is_integrated_title(app.main.win) {
		return
	}
	quiet := ui.Button_Options{face = ui.Button_Face.Ghost, quiet = true}
	if ui.button("form_settings", i18n.tr("Settings"), o = quiet).clicked {
		settings_toggle(app)
	}
	if ui.button("form_about", i18n.tr("About"), o = quiet).clicked {
		about(app)
	}
}

screen_build :: proc(app: ^App) {
	// The pointer moves a screen larger than the window at 1:1; with no pointer, the screen stays where it was.
	if app.host_pointer_valid {
		app.pan_pointer = app.host_pointer
	}
	app.placement_of_screen, _ = layout.place(app.area, app.screen.width, app.screen.height, app.scale_mode, app.pan_pointer)
	if app.arrow_texture == 0 {
		arrow_texture_make(app)
	}
	ui.next({width = ui.fill(), height = ui.fill()})
	ui.custom("screen", draw_screen, app)
	bar_build(app)
}

// draw_screen draws the screen of the machine where the placement puts it, then the pointer of the machine when the
// host cursor is not the cursor. The box gives the area of the next frame: the room under the title bar.
draw_screen :: proc(box: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	app := (^App)(user)
	app.area = {box.rect.min, box.rect.max}
	if app.texture == 0 || app.placement_of_screen.scale <= 0 {
		return
	}
	draw.image(dc, app.texture, draw.Rect{app.placement_of_screen.rect.min, app.placement_of_screen.rect.max})
	// The texture holds a whole viewer frame once one came: the first frame of a session covers the whole screen.
	app.screen_drawn = app.frames >= 1
	if app.frames != app.frames_drawn {
		app.frames_drawn = app.frames
		measure_presented(&app.measure, time.tick_now())
	}
	// While the machine holds the input and the host pointer is over the screen, the host cursor is the cursor: it moves
	// at once. Else the pointer of the machine is drawn at its last place.
	_, _, host_over := screen_place(app, app.host_pointer)
	if app.input_held && app.host_pointer_valid && host_over {
		return
	}
	pointer := app.pointer
	// A rectangle of four zeros covers nothing: the machine draws no pointer.
	if (pointer.right == 0 && pointer.bottom == 0) || app.arrow_texture == 0 {
		return
	}
	side := f32(app.arrow_size)
	tip := app.placement_of_screen.rect.min + [2]f32{f32(pointer.x), f32(pointer.y)} * app.placement_of_screen.scale
	draw.image(dc, app.arrow_texture, {{math.floor(tip.x), math.floor(tip.y)}, {math.floor(tip.x) + side, math.floor(tip.y) + side}})
}

// arrow_texture_make draws the arrow of the pointer of the machine once, at the scale of the window.
arrow_texture_make :: proc(app: ^App) {
	side := max(int(math.round(ARROW_SIZE * app.main.win.dpi_scale)), 1)
	picture := arrow_draw(side, context.temp_allocator)
	app.arrow_texture = render.create_texture_rgba(&app.shared.r, side, side, mips = false)
	if app.arrow_texture != 0 {
		render.update_texture_rgba(&app.shared.r, app.arrow_texture, 0, 0, side, side, picture.pixels)
	}
	app.arrow_size = side
}
