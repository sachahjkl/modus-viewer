// modus viewer: the screen of a modus machine in a window, and the keys and the pointer of the user to it
// (src/md/README.md, src/md/features/window.md).
package modus_viewer

import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:thread"
import "gt:draw"
import host "gt:host"
import "gt:platform"
import "gt:render"
import "gt:ui"
import protocol "modus:contract/remote_display"
import "connection"
import "session"

APP_NAME :: "modus-viewer"
APP_VERSION :: "0.0.0"
WINDOW_TITLE :: "modus viewer"
USAGE :: "usage: modus-viewer [-address:<host>:<port>] [-machine-key:<64 hexadecimal digits>] [-input]"

// Why the form does not start a connection.
Form_Problem :: enum u8 {
	None,
	Address_Empty,
	Port_Out_Of_Range,
	Machine_Key_Not_Hexadecimal,
	Viewer_Key_Not_Ready,
}

@(rodata)
FORM_PROBLEM_SENTENCES := [Form_Problem]string {
	.None                        = "",
	.Address_Empty               = "Give the address of the machine: a name or an IPv4 address, then :port if it is not 7101.",
	.Port_Out_Of_Range           = "The port is a number from 1 to 65535.",
	.Machine_Key_Not_Hexadecimal = "The machine key is 64 hexadecimal digits: the key that remote_display writes on the log of the machine.",
	.Viewer_Key_Not_Ready        = "The viewer has no key yet: the sentence under its line says why.",
}

App :: struct {
	shared:           host.Shared,
	main:             host.Host,
	key:              Viewer_Key,
	key_worker:       ^thread.Thread,
	// The form.
	allow_line:       ui.Line_Edit,
	address:          ui.Line_Edit,
	machine_key:      ui.Line_Edit,
	input:            bool,
	connect_at_start: bool,
	form_problem:     Form_Problem,
	end_sentence:     string, // The sentence of the last end: owned.
	// The session.
	viewer_connection: ^connection.Connection,
	session_address:  string, // Owned.
	session_input:    bool,
	connected:        bool,
	end_asked:        bool,
	texture:          render.Texture,
	texture_screen:   protocol.Screen,
	screen:           protocol.Screen,
	pointer:          protocol.Pointer_Place_Body,
	frames:           u64,
	screen_rect:      draw.Rect, // Where the last frame drew the screen: the place of the pointer of the user maps from it.
	// The input: a press waits for its character in the same batch of events.
	pending_key:      protocol.Key_Body,
	has_pending_key:  bool,
	pending_release:  bool, // A key that the toolkit does not name has no release event: the release goes with the press.
	pointer_buttons:  u32,
	wheel_rest:       f32,
}

main :: proc() {
	app := new(App)
	defer free(app)
	address_argument, key_argument := "", ""
	for argument in os.args[1:] {
		switch {
		case strings.has_prefix(argument, "-address:"):
			address_argument = argument[len("-address:"):]
		case strings.has_prefix(argument, "-machine-key:"):
			key_argument = argument[len("-machine-key:"):]
		case argument == "-input":
			app.input = true
		case:
			fmt.eprintln(USAGE)
			os.exit(2)
		}
	}
	app.connect_at_start = address_argument != "" && key_argument != ""
	// The viewer key and each connection need the generator of the operating system: with none, the viewer stops now.
	probe: [32]u8
	if !connection.system_random_fill(probe[:]) {
		fmt.eprintln("modus-viewer: the generator of the operating system gave no random bytes: the viewer cannot make its key or a connection, and stops")
		os.exit(1)
	}
	connection.erase_secret_bytes(&probe, size_of(probe))

	if !host.host_open(&app.main, &app.shared, {title = WINDOW_TITLE, size = {1280, 860}}, build, app) {
		os.exit(1)
	}
	app.main.input = input_hook
	app.main.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	platform.set_dark_title(app.main.win, true)
	ui.line_edit_set(&app.address, address_argument)
	ui.line_edit_set(&app.machine_key, key_argument)
	viewer_key_load_start(app)

	platform.show_window(app.main.win)
	for !platform.is_closed(app.main.win) {
		host.hosts_wait({&app.main})
		host.host_frame(&app.main)
	}

	// The window is gone: the end of the connection and the worker can be waited for.
	if app.viewer_connection != nil {
		connection.connection_end_and_wait(app.viewer_connection)
		app.viewer_connection = nil
	}
	thread.join(app.key_worker)
	thread.destroy(app.key_worker)
	// The posts that wait free what they carry; none may start a connection now.
	app.connect_at_start = false
	_ = ui.drain_posts(&app.main.state)
	if app.texture != 0 {
		render.destroy_texture(&app.shared.r, app.texture)
	}
	ui.line_edit_destroy(&app.allow_line)
	ui.line_edit_destroy(&app.address)
	ui.line_edit_destroy(&app.machine_key)
	delete(app.end_sentence)
	delete(app.session_address)
	host.host_close(&app.main)
}

// app_key_ready runs when the viewer key arrived.
app_key_ready :: proc(app: ^App) {
	allow_line_update(app)
	if app.connect_at_start {
		app.connect_at_start = false
		form_connect(app)
	}
	host.host_settle(&app.main)
}

// allow_line_update writes the line that allows the viewer key, with the uses that the switch of the input names.
allow_line_update :: proc(app: ^App) {
	if app.key.origin == .Loading || app.key.origin == .No_System_Random {
		return
	}
	uses := app.input ? "view_and_input" : "view"
	ui.line_edit_set(&app.allow_line, fmt.tprintf("remote_display_allow(\"%s\", \"%s\")", hex_of(app.key.public_key[:]), uses))
}

////////////////////////////////
// The views

build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	if app.viewer_connection != nil {
		build_session(app)
	} else {
		build_form(app)
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
			if app.end_sentence != "" {
				ui.spacer(ui.px(em * 0.5))
				ui.paragraph(fmt.tprintf("%s###end", app.end_sentence))
			}
		}
	}
}

build_session :: proc(app: ^App) {
	em := ui.font_size()
	ui.next({width = ui.fill(), height = ui.px(em * 2.4)})
	if ui.row(.Center) {
		ui.spacer(ui.px(em * 0.6))
		ui.next({width = ui.text_size(), height = ui.px(em * 2)})
		ui.label(fmt.tprintf("%s###status", session_status(app)))
		ui.spacer(ui.fill())
		if !app.end_asked {
			ui.next({width = ui.text_size(em), height = ui.px(em * 2)})
			if ui.button("disconnect", "Disconnect").clicked {
				app.end_asked = true
				connection.connection_end(app.viewer_connection)
			}
		}
		ui.spacer(ui.px(em * 0.6))
	}
	ui.next({width = ui.fill(), height = ui.fill()})
	ui.custom("screen", draw_screen, app)
}

// session_status says where the session is, in the bar: the address, then the size of the screen once it shows.
session_status :: proc(app: ^App) -> string {
	switch {
	case app.end_asked:
		return fmt.tprintf("%s: ending the session", app.session_address)
	case !app.connected:
		return fmt.tprintf("%s: connecting", app.session_address)
	case app.frames == 0:
		return fmt.tprintf("%s: waiting for the first frame", app.session_address)
	}
	return fmt.tprintf("%s, %d × %d%s", app.session_address, app.screen.width, app.screen.height, app.session_input ? ", input on" : "")
}

// draw_screen draws the screen of the machine scaled to the box, with its proportions, then the mark of its pointer.
draw_screen :: proc(box: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	app := (^App)(user)
	area := box.rect
	if app.texture == 0 || app.screen.width == 0 || app.screen.height == 0 {
		app.screen_rect = {}
		return
	}
	area_width, area_height := area.max.x - area.min.x, area.max.y - area.min.y
	scale := min(area_width / f32(app.screen.width), area_height / f32(app.screen.height))
	width, height := f32(app.screen.width) * scale, f32(app.screen.height) * scale
	left, top := area.min.x + (area_width - width) * 0.5, area.min.y + (area_height - height) * 0.5
	app.screen_rect = {{left, top}, {left + width, top + height}}
	draw.image(dc, app.texture, app.screen_rect)
	// A rectangle of four zeros covers nothing: the machine draws no pointer.
	pointer := app.pointer
	if pointer.right != 0 || pointer.bottom != 0 {
		x, y := left + (f32(pointer.x) + 0.5) * scale, top + (f32(pointer.y) + 0.5) * scale
		draw.rect(dc, {{x - 6, y - 6}, {x + 6, y + 6}}, {0, 0, 0, 0.75}, radius = 6)
		draw.rect(dc, {{x - 4, y - 4}, {x + 4, y + 4}}, {1, 1, 1, 1}, radius = 4)
	}
}

////////////////////////////////
// The connection

form_connect :: proc(app: ^App) {
	if app.key.origin == .Loading || app.key.origin == .No_System_Random {
		app.form_problem = .Viewer_Key_Not_Ready
		return
	}
	host_name, port, address_problem := parse_address(ui.line_edit_string(&app.address))
	if address_problem != .None {
		app.form_problem = address_problem
		return
	}
	machine_key, key_ok := parse_machine_key(ui.line_edit_string(&app.machine_key))
	if !key_ok {
		app.form_problem = .Machine_Key_Not_Hexadecimal
		return
	}
	app.form_problem = .None
	delete(app.end_sentence)
	app.end_sentence = ""
	delete(app.session_address)
	app.session_address = fmt.aprintf("%s:%d", host_name, port)
	app.session_input = app.input
	app.connected = false
	app.end_asked = false
	app.screen = {}
	app.pointer = {}
	app.frames = 0
	app.screen_rect = {}
	app.has_pending_key = false
	app.pointer_buttons = 0
	app.wheel_rest = 0
	settings := connection.Settings {
		host               = host_name,
		port               = port,
		machine_key        = machine_key,
		viewer_private_key = app.key.private_key,
		input              = app.input,
	}
	app.viewer_connection = connection.connection_start(settings, connection_wake, app)
}

// connection_wake runs on the thread of the connection: it only posts to the window.
connection_wake :: proc(user: rawptr) {
	app := (^App)(user)
	// false: the window is gone, and the exit of the program waits for this thread.
	_ = ui.post(&app.main.state, connection_changed, app)
}

// connection_changed runs on the interface thread: it uploads the damage, takes the pointer and the end.
connection_changed :: proc(data: rawptr, _: u64) {
	app := (^App)(data)
	c := app.viewer_connection
	if c == nil {
		// A post of a connection that ended before it ran.
		return
	}
	r := &app.shared.r
	p := connection.picture_lock(c)
	if p.screen.width != 0 && (p.screen_changed || app.texture_screen != p.screen) {
		if app.texture != 0 {
			render.destroy_texture(r, app.texture)
		}
		width, height := int(p.screen.width), int(p.screen.height)
		app.texture = render.create_texture_rgba(r, width, height, mips = false)
		app.texture_screen = p.screen
		if app.texture != 0 {
			render.update_texture_rgba(r, app.texture, 0, 0, width, height, p.rgba[:width * height * 4])
		}
		p.screen_changed = false
		p.damage_count = 0
	}
	if app.texture != 0 {
		stride := int(p.screen.width) * 4
		for rectangle in p.damage[:p.damage_count] {
			offset := int(rectangle.y) * stride + int(rectangle.x) * 4
			render.update_texture_rgba(r, app.texture, int(rectangle.x), int(rectangle.y), int(rectangle.width), int(rectangle.height), p.rgba[offset:], stride = stride)
		}
	}
	p.damage_count = 0
	app.screen, app.pointer, app.frames, app.connected = p.screen, p.pointer, p.frames, p.connected
	ended, end := p.ended, p.end
	connection.picture_unlock(c)
	if ended {
		connection.connection_destroy(c)
		app.viewer_connection = nil
		app.end_sentence = session.end_sentence(end)
		if app.texture != 0 {
			render.destroy_texture(r, app.texture)
			app.texture, app.texture_screen = 0, {}
		}
	}
	host.host_settle(&app.main)
}

// parse_address reads "host" or "host:port". A name or an IPv4 address: an IPv6 address is not read yet.
parse_address :: proc(text: string) -> (host_name: string, port: u16, problem: Form_Problem) {
	trimmed := strings.trim_space(text)
	colon := strings.last_index_byte(trimmed, ':')
	if colon < 0 {
		return trimmed, connection.DEFAULT_PORT, trimmed == "" ? .Address_Empty : .None
	}
	host_name = trimmed[:colon]
	if host_name == "" {
		return "", 0, .Address_Empty
	}
	value, ok := strconv.parse_uint(trimmed[colon + 1:], 10)
	if !ok || value == 0 || value > 65535 {
		return "", 0, .Port_Out_Of_Range
	}
	return host_name, u16(value), .None
}

// parse_machine_key reads the 64 hexadecimal digits of an Ed25519 public key.
parse_machine_key :: proc(text: string) -> (key: [32]u8, ok: bool) {
	trimmed := strings.trim_space(text)
	if len(trimmed) != 64 {
		return {}, false
	}
	decoded, decoded_ok := hex.decode(transmute([]u8)trimmed, context.temp_allocator)
	if !decoded_ok || len(decoded) != 32 {
		return {}, false
	}
	copy(key[:], decoded)
	return key, true
}

hex_of :: proc(bytes: []u8) -> string {
	return string(hex.encode(bytes, context.temp_allocator))
}

////////////////////////////////
// The input

// input_hook sends the keys and the pointer to the machine while the input of the session is on. The events that go
// to the machine do not reach the interface; a press on the bar does.
input_hook :: proc(h: ^host.Host, events: []platform.Event) -> []platform.Event {
	app := (^App)(h.user)
	c := app.viewer_connection
	if c == nil || !app.session_input || !app.connected || app.end_asked || app.screen.width == 0 {
		return events
	}
	kept := make([dynamic]platform.Event, 0, len(events), context.temp_allocator)
	for event in events {
		if !input_take(app, c, event) {
			append(&kept, event)
		}
	}
	pending_flush(app, c)
	return kept[:]
}

// input_take sends one event to the machine, and says if the machine took it.
input_take :: proc(app: ^App, c: ^connection.Connection, event: platform.Event) -> bool {
	#partial switch event.kind {
	case .Key_Press:
		pending_flush(app, c)
		code := event.key != .None ? scan_code_of_key(event.key) : scan_code_of_character(event.char)
		if code != 0 {
			app.pending_key = {code = code, pressed = 1, modifiers = modifiers_of(event.mods)}
			app.has_pending_key = true
			app.pending_release = event.key == .None
		}
		return true
	case .Key_Release:
		pending_flush(app, c)
		if code := scan_code_of_key(event.key); event.key != .None && code != 0 {
			connection.connection_input(c, protocol.Key_Body{code = code, modifiers = modifiers_of(event.mods)})
		}
		return true
	case .Text:
		character := u32(event.text)
		printable := character >= 0x20 && character != 0x7F
		if app.has_pending_key {
			if printable {
				app.pending_key.character = character
			}
			pending_flush(app, c)
		} else if code := scan_code_of_character(event.text); printable && code != 0 {
			// A character with no press before it: its key goes pressed and released.
			connection.connection_input(c, protocol.Key_Body{code = code, character = character, pressed = 1})
			connection.connection_input(c, protocol.Key_Body{code = code})
		}
		return true
	case .Mouse_Move, .Mouse_Press, .Mouse_Release:
		x, y, inside := screen_place(app, event.pos)
		// A drag that started on the screen stays the machine's until its release.
		if !inside && app.pointer_buttons == 0 {
			return false
		}
		app.pointer_buttons = buttons_of(event.buttons)
		connection.connection_input(c, protocol.Pointer_Body{x = x, y = y, buttons = app.pointer_buttons})
		return true
	case .Scroll:
		x, y, inside := screen_place(app, event.pos)
		if !inside {
			return false
		}
		// A notch toward the user (positive y) moves the view toward the end of its content, as on the machine.
		app.wheel_rest += event.delta.y
		notches := clamp(i32(app.wheel_rest), -protocol.WHEEL_NOTCHES_LIMIT, protocol.WHEEL_NOTCHES_LIMIT)
		app.wheel_rest -= f32(notches)
		if notches != 0 {
			connection.connection_input(c, protocol.Pointer_Body{x = x, y = y, buttons = app.pointer_buttons, wheel = notches})
		}
		return true
	}
	return false
}

// pending_flush sends the press that waited for its character.
pending_flush :: proc(app: ^App, c: ^connection.Connection) {
	if !app.has_pending_key {
		return
	}
	app.has_pending_key = false
	connection.connection_input(c, app.pending_key)
	if app.pending_release {
		connection.connection_input(c, protocol.Key_Body{code = app.pending_key.code, modifiers = app.pending_key.modifiers})
	}
}

// screen_place maps a place of the window to a pixel of the screen of the machine, clamped to the screen.
screen_place :: proc(app: ^App, place: [2]f32) -> (x, y: u32, inside: bool) {
	r := app.screen_rect
	if r.max.x <= r.min.x || r.max.y <= r.min.y {
		return 0, 0, false
	}
	inside = place.x >= r.min.x && place.x < r.max.x && place.y >= r.min.y && place.y < r.max.y
	column := (place.x - r.min.x) / (r.max.x - r.min.x) * f32(app.screen.width)
	row := (place.y - r.min.y) / (r.max.y - r.min.y) * f32(app.screen.height)
	x = u32(clamp(column, 0, f32(app.screen.width - 1)))
	y = u32(clamp(row, 0, f32(app.screen.height - 1)))
	return x, y, inside
}
