package modus_viewer

// The views of the window (src/md/features/interface.md): the form, the message of a connection that starts or ended,
// and the screen of the machine with its floating bar.

import "core:fmt"
import "core:math"
import "core:time"
import "gt:draw"
import host "gt:host"
import "gt:platform"
import "gt:render"
import "gt:ui"
import "layout"

// What the window shows. Derived each frame from what the window holds, never stored.
View_State :: enum u8 {
	Form,       // No session was asked yet.
	Connecting, // A connection runs, or starts with the viewer, and no whole frame came.
	Screen,     // A whole frame came: the screen of the machine, alone.
	Ended,      // The last connection ended: its sentence, Retry, and Change the address.
}

// The bar: its height, its widest, its gap to the top of the screen area, and its side margins, in em.
BAR_HEIGHT_EM :: f32(2.4)
BAR_WIDTH_EM :: f32(46)
BAR_TOP_GAP_EM :: f32(0.4)
BAR_MARGIN_EM :: f32(0.8)
// The round trip under which the dot is green, in milliseconds: a key then shows within about three frames of 60 Hz.
GOOD_ROUND_TRIP_MILLISECONDS :: 50
// The side of the arrow of the pointer of the machine, in logical pixels: the size of the pointer theme of modus.
ARROW_SIZE :: 24
// The width of the text of a centred message, in em.
MESSAGE_WIDTH_EM :: f32(30)

view_state :: proc(app: ^App) -> View_State {
	switch {
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
	app.area = {{0, 0}, size}
	switch view_state(app) {
	case .Form:
		build_form(app)
	case .Connecting:
		// Before the viewer key arrives, a session that starts with the viewer has no machine name yet.
		build_message(app, app.machine_name != "" ? fmt.tprintf("Connecting to %s", app.machine_name) : "Connecting", "", false)
	case .Ended:
		build_message(app, fmt.tprintf("The session with %s ended", app.machine_name), app.end_sentence, true)
	case .Screen:
		build_screen(app, size)
	}
	if app.toast_due != .None {
		// A hint about the window itself: in_window keeps it a toast, never a notification of the system.
		announcer: ui.Announcer
		ui.announce(&announcer, .Info, app.toast_due == .Released ? INPUT_RELEASED_TOAST : INPUT_HELD_TOAST, in_window = true)
		app.toast_due = .None
	}
}

build_form :: proc(app: ^App) {
	em := ui.font_size()
	ui.spacer(ui.px(em))
	ui.next({width = ui.fill()})
	if ui.row() {
		ui.spacer(ui.px(em))
		ui.next({width = ui.px(em * 40)})
		if ui.column() {
			ui.label("Allow this viewer in a console of the machine:###allow_title")
			ui.next({width = ui.fill()})
			ui.line_edit("###allow", &app.allow_line, {kind = .Read_Only, placeholder = VIEWER_KEY_ORIGIN_SENTENCES[.Loading]})
			if sentence := VIEWER_KEY_ORIGIN_SENTENCES[app.key.origin]; sentence != "" && app.key.origin != .Loading {
				ui.paragraph(fmt.tprintf("%s###origin", sentence))
			}
			ui.spacer(ui.px(em))
			ui.label("Address of the machine###address_title")
			ui.next({width = ui.fill()})
			ui.line_edit("###address", &app.address, {placeholder = "host:7101"})
			ui.spacer(ui.px(em * 0.5))
			ui.label("Machine key###machine_key_title")
			ui.next({width = ui.fill()})
			ui.line_edit("###machine_key", &app.machine_key, {placeholder = "the public key that remote_display writes on the log of the machine"})
			ui.spacer(ui.px(em * 0.5))
			if ui.toggle("input", "Send my keys and my pointer", &app.input) {
				allow_line_update(app)
			}
			ui.spacer(ui.px(em))
			if ui.button("connect", "Connect", o = {intent = .Primary}).clicked {
				form_connect(app)
			}
			if app.form_problem != .None {
				ui.spacer(ui.px(em * 0.5))
				ui.paragraph(fmt.tprintf("%s###form_problem", FORM_PROBLEM_SENTENCES[app.form_problem]))
			}
		}
	}
}

// build_message centres a title, a sentence and, after an end, Retry and Change the address on the background.
build_message :: proc(app: ^App, title, sentence: string, ended: bool) {
	em := ui.font_size()
	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.column(.Center) {
		ui.spacer(ui.fill())
		ui.next({width = ui.text_size(), height = ui.px(em * 2)})
		ui.label(fmt.tprintf("%s###message_title", title))
		if sentence != "" {
			ui.spacer(ui.px(em * 0.5))
			ui.next({width = ui.px(em * MESSAGE_WIDTH_EM)})
			ui.paragraph(fmt.tprintf("%s###message_sentence", sentence))
		}
		if ended {
			ui.spacer(ui.px(em))
			ui.next({width = ui.text_size()})
			if ui.row(.Center) {
				if ui.button("retry", "Retry", o = {intent = .Primary}).clicked {
					session_retry(app)
				}
				ui.spacer(ui.px(em * 0.6))
				if ui.button("change_address", "Change the address").clicked {
					session_forget(app)
				}
			}
		}
		ui.spacer(ui.fill())
	}
}

build_screen :: proc(app: ^App, size: host.Vec2) {
	// The pointer moves a screen larger than the window at 1:1; with no pointer, the screen stays where it was.
	if app.host_pointer_valid {
		app.pan_pointer = app.host_pointer
	}
	app.placement, _ = layout.place(app.area, app.screen.width, app.screen.height, app.scale_mode, app.pan_pointer)
	if app.arrow_texture == 0 {
		arrow_texture_make(app)
	}
	ui.next({width = ui.fill(), height = ui.fill()})
	ui.custom("screen", draw_screen, app)
	bar_hover_update(app)
	if bar_shown(app) {
		build_bar(app, size)
	}
}

// bar_shown: the pointer asked for the bar, or the screenshot asks for it.
bar_shown :: proc(app: ^App) -> bool {
	return app.bar_forced || layout.hover_shows_bar(app.hover)
}

// bar_hover_update moves the state machine of the bar on the place of the host pointer, and asks for a wake at its
// next deadline.
bar_hover_update :: proc(app: ^App) {
	em := ui.font_size()
	at := app.host_pointer
	area := app.area
	inside := app.host_pointer_valid && at.x >= area.min.x && at.x < area.max.x && at.y >= area.min.y && at.y < area.max.y
	in_band := inside && at.y < area.min.y + em * ui.VIEW_HOVER_EDGE_EM
	over_bar := app.host_pointer_valid && at.x >= app.bar_rect.min.x && at.x < app.bar_rect.max.x && at.y >= app.bar_rect.min.y && at.y < app.bar_rect.max.y
	now := f64(time.duration_milliseconds(time.tick_since(app.started)))
	if wake := layout.hover_step(&app.hover, now, in_band, over_bar && bar_shown(app), app.host_buttons_down, ui.VIEW_HOVER_DWELL_MS); wake > 0 {
		ui.wake_within(&app.main.state, wake)
	}
}

build_bar :: proc(app: ^App, size: host.Vec2) {
	em := ui.font_size()
	width := min(size.x - 2 * em * BAR_MARGIN_EM, em * BAR_WIDTH_EM)
	height := em * BAR_HEIGHT_EM
	left := math.floor((size.x - width) / 2)
	top := math.floor(em * BAR_TOP_GAP_EM)
	app.bar_rect = {{left, top}, {left + width, top + height}}
	now := time.tick_now()
	fps := frames_in_last_second(&app.measure, now)
	// The frames of the last second fall to 0 on a still screen: the bar reads them again each second while it shows.
	ui.wake_within(&app.main.state, 1000)
	quality := "measuring"
	app.dot_color = ui.color("weak")
	switch {
	case app.lost:
		quality = "lost"
		app.dot_color = ui.color("red")
	case app.round_trip_microseconds > 0:
		milliseconds := app.round_trip_microseconds / 1000
		quality = fmt.tprintf("%d ms · %d fps", milliseconds, fps)
		app.dot_color = ui.color(milliseconds < GOOD_ROUND_TRIP_MILLISECONDS ? "green" : "yellow")
	}
	ui.push_tags("floating")
	ui.next({fixed_x = left, fixed_y = top, fixed_w = width, fixed_h = height, radius = em * 0.6})
	if ui.row(.Center, {.Draw_Background, .Draw_Border, .Draw_Shadow, .Clip}, "###bar") {
		ui.pop_tags()
		ui.spacer(ui.px(em * 0.8))
		ui.next({width = ui.text_size(), height = ui.px(em * 2)})
		ui.label(fmt.tprintf("%s###bar_name", app.machine_name))
		ui.spacer(ui.px(em))
		ui.next({width = ui.px(em * 0.6), height = ui.px(em * 0.6)})
		ui.custom("bar_dot", draw_dot, app)
		ui.spacer(ui.px(em * 0.4))
		ui.next({width = ui.text_size(), height = ui.px(em * 2)})
		ui.label(fmt.tprintf("%s###bar_quality", quality))
		ui.spacer(ui.fill())
		// Each button names what it does: the other scale, the other mode.
		ghost := ui.Button_Options{size = .Small, face = ui.Button_Face.Ghost}
		if ui.button("bar_scale", app.scale_mode == .Fit ? "1:1" : "Fit", o = ghost).clicked {
			app.scale_mode = app.scale_mode == .Fit ? layout.Scale_Mode.One_To_One : layout.Scale_Mode.Fit
		}
		full := platform.is_fullscreen(app.main.win)
		if ui.button("bar_full_screen", full ? "Window" : "Full screen", o = ghost).clicked {
			platform.set_fullscreen(app.main.win, !full)
		}
		held := app.input_held
		if ui.toggle("bar_input", "Input", &held) {
			input_hold(app, held)
		}
		ui.spacer(ui.px(em * 0.4))
		if ui.button("bar_disconnect", "Disconnect", o = {size = .Small}).clicked {
			app.end_asked = true
			connection_end_asked(app)
		}
		ui.spacer(ui.px(em * 0.8))
	}
}

// draw_screen draws the screen of the machine where the placement puts it, then the pointer of the machine when the
// host cursor is not the cursor.
draw_screen :: proc(box: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	app := (^App)(user)
	if app.texture == 0 || app.placement.scale <= 0 {
		return
	}
	draw.image(dc, app.texture, draw.Rect{app.placement.rect.min, app.placement.rect.max})
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
	tip := app.placement.rect.min + [2]f32{f32(pointer.x), f32(pointer.y)} * app.placement.scale
	draw.image(dc, app.arrow_texture, {{math.floor(tip.x), math.floor(tip.y)}, {math.floor(tip.x) + side, math.floor(tip.y) + side}})
}

draw_dot :: proc(box: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	app := (^App)(user)
	r := box.rect
	draw.rect(dc, r, app.dot_color, radius = (r.max.x - r.min.x) / 2)
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
