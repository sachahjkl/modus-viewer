package modus_viewer

// The bar of the machine (src/md/features/interface.md, "The bar"): a plate of the machined finish, docked to an edge,
// floating over the screen, or solo in a small window of its own. Its place is the pure layout.Bar_Place; this file
// draws it, moves it with its handle, and opens and closes the solo window.

import "core:fmt"
import "core:math"
import "core:time"
import "gt:draw"
import host "gt:host"
import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import "gt:ui"
import "layout"

// The bar in em: its length and thickness along its own axis, horizontal and vertical, its gap to the edges, and the
// distance under which a drop docks to an edge (the toolkit has no snap distance of its own).
BAR_LENGTH_EM :: f32(56)
BAR_THICKNESS_EM :: f32(2.6)
BAR_VERTICAL_LENGTH_EM :: f32(24)
BAR_VERTICAL_THICKNESS_EM :: f32(9)
BAR_GAP_EM :: f32(0.4)
BAR_SNAP_EM :: f32(2)
// The soft shadow of the plate, in logical pixels: the find bar of the toolkit has one of the same kind.
BAR_SHADOW_PX :: f32(8)
// The thickness of the mark of the edge that a drop would dock on, in logical pixels.
SNAP_MARK_PX :: f32(3)
// The round trip under which the lamp is green, in milliseconds: a key then shows within about three frames of 60 Hz.
GOOD_ROUND_TRIP_MILLISECONDS :: 50

Bar_State :: struct {
	forced:       bool, // -screenshot-bar: drawn as pinned.
	hover:        layout.Hover,
	rect:         layout.Rect, // Where the bar is drawn in the window this frame; empty when it is hidden or solo.
	// A move by the handle: the bar follows the pointer as a floating bar until the release.
	dragging:     bool,
	drag_origin:  [2]f32,
	drag_at:      [2]f32,
	drag_pointer: [2]f32,
	drag_before:  layout.Bar_Place,
	// The solo window.
	solo:         host.Host,
	solo_open:    bool,
	solo_closing: bool,
}

// bar_lengths gives the length and the thickness of the bar, in pixels of the window, along its own axis.
bar_lengths :: proc(vertical: bool) -> (length, thickness: f32) {
	em := ui.font_size()
	if vertical {
		return math.round(em * BAR_VERTICAL_LENGTH_EM), math.round(em * BAR_VERTICAL_THICKNESS_EM)
	}
	return math.round(em * BAR_LENGTH_EM), math.round(em * BAR_THICKNESS_EM)
}

// bar_build places the bar over the screen, follows the pointer that asks for it, and builds it when it shows.
bar_build :: proc(app: ^App) {
	place := layout.bar_place_or_default(app.settings.bar_place)
	em := ui.font_size()
	gap := math.round(em * BAR_GAP_EM)
	horizontal_length, horizontal_thickness := bar_lengths(false)
	vertical_length, _ := bar_lengths(true)
	if _, solo := place.(layout.Bar_Solo); solo && !app.headless {
		app.bar.rect = {}
		return
	}
	vertical := layout.bar_vertical(place)
	length, thickness := bar_lengths(vertical)
	rect, _ := layout.bar_rect(place, app.area, length, thickness, gap)
	if app.bar.dragging {
		vertical = false
		rect = {app.bar.drag_at, app.bar.drag_at + {horizontal_length, horizontal_thickness}}
		preview := layout.bar_drop(app.bar.drag_at, app.bar.drag_pointer, app.area, horizontal_length, horizontal_thickness, vertical_length, gap, math.round(em * BAR_SNAP_EM), app.bar.drag_before)
		if docked, is_docked := preview.(layout.Bar_Docked); is_docked {
			snap_mark_build(app, docked.edge)
		}
	}
	// Pinned, dragged or asked for by the pointer in its zone.
	pointer := app.host_pointer
	in_zone := app.host_pointer_valid && layout.bar_in_zone(place, app.area, rect, pointer, em * ui.VIEW_HOVER_EDGE_EM)
	over_bar := app.host_pointer_valid && inside_rect(app.bar.rect, pointer)
	now := f64(time.duration_milliseconds(time.tick_since(app.started)))
	if wake := layout.hover_step(&app.bar.hover, now, in_zone, over_bar, app.host_buttons_down && !app.bar.dragging, ui.VIEW_HOVER_DWELL_MS); wake > 0 {
		ui.wake_within(&app.main.state, wake)
	}
	shown := app.bar.forced || app.settings.bar_pinned || app.bar.dragging || layout.hover_shows_bar(app.bar.hover)
	if !shown {
		app.bar.rect = {}
		return
	}
	app.bar.rect = rect
	ui.next({fixed_x = rect.min.x, fixed_y = rect.min.y, fixed_w = rect.max.x - rect.min.x, fixed_h = rect.max.y - rect.min.y, axis = vertical ? .Y : .X, cross = .Center, radius = math.round(em * ui.shape_of(.Control))})
	plate := ui.build_box({.Plate, .Clickable}, "###bar")
	plate.plate = ui.frame_new(ui.Plate_Look)
	face := ui.color("card background")
	plate.plate^ = {top = face, bottom = face, shadow = BAR_SHADOW_PX}
	if ui.parent(plate) {
		bar_controls(app, vertical, false)
	}
}

// bar_controls builds what the bar holds, each fact once: the handle, the name, the lamp and its numbers, then the acts.
// In the solo window the handle gives way to the act that puts the bar back.
bar_controls :: proc(app: ^App, vertical, solo: bool) {
	em := ui.font_size()
	ui.space(ui.SPACE_2)
	if !solo {
		handle_build(app, vertical)
		ui.space(ui.SPACE_2)
	}
	if vertical {
		ui.next({width = ui.fill()})
	} else {
		ui.next({width = ui.text_size(), height = ui.px(em * 2)})
	}
	ui.label(fmt.tprintf("%s###bar_name", app.machine_name))
	ui.space(ui.SPACE_3)
	quality_build(app, vertical)
	if vertical {
		ui.space(ui.SPACE_3)
	} else {
		ui.spacer(ui.fill())
	}
	small := ui.Button_Options{size = .Small, face = ui.Button_Face.Ghost}
	icon := ui.Button_Options{size = .Small, face = ui.Button_Face.Ghost, icon_font = ui.lucide_icons()}
	control_next(vertical)
	if ui.button("bar_scale", app.scale_mode == .Fit ? i18n.tr("1:1") : i18n.tr("Fit"), o = small).clicked {
		app.scale_mode = app.scale_mode == .Fit ? layout.Scale_Mode.One_To_One : layout.Scale_Mode.Fit
	}
	full := platform.is_fullscreen(app.main.win)
	control_next(vertical)
	if ui.button("bar_full_screen", full ? i18n.tr("Window") : i18n.tr("Full screen"), o = small).clicked {
		platform.set_fullscreen(app.main.win, !full)
	}
	held := app.input_held
	control_next(vertical)
	if ui.toggle("bar_input", i18n.tr("Input"), &held) {
		input_hold(app, held)
	}
	if !solo {
		pin := icon
		pin.tip = app.settings.bar_pinned ? i18n.tr("Let the bar hide") : i18n.tr("Keep the bar shown")
		pin.lit = app.settings.bar_pinned
		control_next(vertical)
		if ui.button("bar_pin", icon = app.settings.bar_pinned ? lucide.PIN : lucide.PIN_OFF, o = pin).clicked {
			bar_pinned_keep(app, !app.settings.bar_pinned)
		}
	}
	detach := icon
	detach.tip = solo ? i18n.tr("Put the bar back in the window") : i18n.tr("Move the bar to a window of its own")
	control_next(vertical)
	if ui.button("bar_detach", icon = solo ? lucide.PICTURE_IN_PICTURE : lucide.PICTURE_IN_PICTURE_2, o = detach).clicked {
		if solo {
			app.bar.solo_closing = true
		} else {
			bar_place_keep(app, layout.bar_detach(app.settings.bar_place))
		}
	}
	settings := icon
	settings.tip = i18n.tr("Settings")
	control_next(vertical)
	if ui.button("bar_settings", icon = lucide.SETTINGS, o = settings).clicked {
		settings_toggle(app)
	}
	ui.space(ui.SPACE_2)
	control_next(vertical)
	if ui.button("bar_disconnect", i18n.tr("Disconnect"), o = {size = .Small, intent = .Danger}).clicked {
		connection_end_asked(app)
	}
	ui.space(ui.SPACE_2)
}

// A control of a vertical bar takes its width; on a horizontal bar, its own.
@(private = "file")
control_next :: proc(vertical: bool) {
	if vertical {
		ui.next({width = ui.fill()})
	}
}

// quality_build shows the lamp of the connection and its numbers (immediacy.md, "The numbers").
@(private = "file")
quality_build :: proc(app: ^App, vertical: bool) {
	em := ui.font_size()
	fps := frames_in_last_second(&app.measure, time.tick_now())
	// The frames of the last second fall to 0 on a still screen: the bar reads them again each second while it shows.
	ui.wake_within(&app.main.state, 1000)
	words := i18n.tr("measuring")
	switch {
	case app.lost:
		words = i18n.tr("lost")
		app.dot_color = ui.color("hue_red")
	case app.round_trip_microseconds > 0:
		milliseconds := app.round_trip_microseconds / 1000
		words = fmt.tprintf("%d ms · %d fps", milliseconds, fps)
		app.dot_color = ui.color(milliseconds < GOOD_ROUND_TRIP_MILLISECONDS ? "hue_green" : "hue_yellow")
	case:
		if ui.tags("faint") {
			app.dot_color = ui.color("text")
		}
	}
	ui.next({height = ui.px(em * 2), axis = .X, cross = .Center, width = vertical ? ui.fill() : ui.children_sum()})
	if ui.row(.Center, id = "###bar_quality") {
		ui.next({width = ui.px(em * 0.8), height = ui.px(em * 0.8)})
		ui.custom("bar_lamp", lamp_draw, app)
		ui.space(ui.SPACE_2)
		ui.next({width = ui.text_size(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###bar_numbers", words))
	}
}

lamp_draw :: proc(box: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	app := (^App)(user)
	r := box.rect
	ui.machined_lamp(dc, (r.min + r.max) / 2, r.max.x - r.min.x, app.dot_color)
}

// handle_build is the handle: two grooves of the finish. Pressed, the bar follows the pointer; released, it docks to the
// nearest edge within the snap distance, floats where it is, or goes solo when the pointer left the screen.
@(private = "file")
handle_build :: proc(app: ^App, vertical: bool) {
	em := ui.font_size()
	if vertical {
		ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.2))})
	} else {
		ui.next({width = ui.px(math.round(em * 1.2)), height = ui.pct(1)})
	}
	handle := ui.build_box({.Clickable, .Draw_Hot_Effects}, "###bar_handle")
	handle.custom, handle.custom_user = handle_draw, rawptr(uintptr(vertical ? 1 : 0))
	handle.cursor = app.bar.dragging ? .Grabbing : .Grab
	signal := ui.signal(handle)
	if signal.pressed && !app.bar.dragging {
		app.bar.dragging = true
		app.bar.drag_origin = app.bar.rect.min
		app.bar.drag_at = app.bar.rect.min
		app.bar.drag_pointer = ui.mouse_pos()
		app.bar.drag_before = app.settings.bar_place
	}
	if !app.bar.dragging {
		return
	}
	if signal.dragging {
		app.bar.drag_at = app.bar.drag_origin + signal.drag_delta
		app.bar.drag_pointer = ui.mouse_pos()
		return
	}
	// Released: the drop decides the place.
	app.bar.dragging = false
	horizontal_length, horizontal_thickness := bar_lengths(false)
	vertical_length, _ := bar_lengths(true)
	gap := math.round(em * BAR_GAP_EM)
	place := layout.bar_drop(app.bar.drag_at, app.bar.drag_pointer, app.area, horizontal_length, horizontal_thickness, vertical_length, gap, math.round(em * BAR_SNAP_EM), app.bar.drag_before)
	bar_place_keep(app, place)
}

handle_draw :: proc(box: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	vertical := uintptr(user) == 1
	r := box.rect
	middle := (r.min + r.max) / 2
	reach := min(r.max.x - r.min.x, r.max.y - r.min.y) * 0.3
	if vertical {
		ui.machined_groove(dc, {middle.x - reach * 2, middle.y - 2}, {middle.x + reach * 2, middle.y - 2})
		ui.machined_groove(dc, {middle.x - reach * 2, middle.y + 2}, {middle.x + reach * 2, middle.y + 2})
	} else {
		ui.machined_groove(dc, {middle.x - 2, middle.y - reach * 2}, {middle.x - 2, middle.y + reach * 2}, vertical = true)
		ui.machined_groove(dc, {middle.x + 2, middle.y - reach * 2}, {middle.x + 2, middle.y + reach * 2}, vertical = true)
	}
}

// snap_mark_build marks the edge that the drop would dock on: a line of the accent along it.
@(private = "file")
snap_mark_build :: proc(app: ^App, edge: layout.Bar_Edge) {
	a := app.area
	r: layout.Rect
	switch edge {
	case .Top:
		r = {a.min, {a.max.x, a.min.y + SNAP_MARK_PX}}
	case .Bottom:
		r = {{a.min.x, a.max.y - SNAP_MARK_PX}, a.max}
	case .Left:
		r = {a.min, {a.min.x + SNAP_MARK_PX, a.max.y}}
	case .Right:
		r = {{a.max.x - SNAP_MARK_PX, a.min.y}, a.max}
	}
	ui.next({fixed_x = r.min.x, fixed_y = r.min.y, fixed_w = r.max.x - r.min.x, fixed_h = r.max.y - r.min.y, bg = ui.color("accent")})
	ui.build_box({.Draw_Background}, "###bar_snap")
}

inside_rect :: proc(r: layout.Rect, at: [2]f32) -> bool {
	return at.x >= r.min.x && at.x < r.max.x && at.y >= r.min.y && at.y < r.max.y
}

////////////////////////////////
// The solo window

// solo_follow opens the solo window when the place asks for it during a session, closes it when it no longer does, and
// draws its frame. Closing it puts the bar back where it was.
solo_follow :: proc(app: ^App) {
	if app.bar.solo_closing {
		app.bar.solo_closing = false
		bar_place_keep(app, layout.bar_solo_back(app.settings.bar_place))
	}
	_, solo := app.settings.bar_place.(layout.Bar_Solo)
	want := solo && !app.headless && view_state(app) == .Screen
	if want && !app.bar.solo_open {
		solo_open(app)
	} else if !want && app.bar.solo_open {
		solo_close(app)
	}
	if app.bar.solo_open && !platform.is_closed(app.bar.solo.win) {
		host.host_frame(&app.bar.solo)
	}
}

@(private = "file")
solo_open :: proc(app: ^App) {
	em := ui.font_size()
	size := [2]int{int(math.round(em * BAR_LENGTH_EM)), int(math.round(em * BAR_THICKNESS_EM * 1.4))}
	if !host.host_open(&app.bar.solo, &app.shared, {title = app.machine_name, size = size}, solo_build, app) {
		// No second window: the bar stays in the window, where it was.
		bar_place_keep(app, layout.bar_solo_back(app.settings.bar_place))
		return
	}
	app.bar.solo.close_asked = proc(h: ^host.Host) {
		app := (^App)(h.user)
		app.bar.solo_closing = true
	}
	app.bar.solo.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	app.bar.solo_open = true
	platform.show_window(app.bar.solo.win)
}

solo_close :: proc(app: ^App) {
	if !app.bar.solo_open {
		return
	}
	app.bar.solo_open = false
	host.host_close(&app.bar.solo)
	app.bar.solo = {}
}

@(private = "file")
solo_build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.row(.Center, id = "###solo_bar") {
		bar_controls(app, false, true)
	}
}
