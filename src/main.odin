// modus viewer: the screen of a modus machine in a window, and the keys and the pointer of the user to it
// (src/md/README.md, src/md/features/interface.md).
package modus_viewer

import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:thread"
import "core:time"
import "gt:draw"
import host "gt:host"
import "gt:platform"
import "gt:render"
import "gt:ui"
import protocol "modus:contract/remote_display"
import "connection"
import "layout"
import "session"

APP_NAME :: "modus-viewer"
APP_VERSION :: "0.0.0"
WINDOW_TITLE :: "modus viewer"
USAGE :: "usage: modus-viewer [-address:<host>:<port>] [-machine-key:<64 hexadecimal digits>] [-input] [-headless] [-screenshot:<file.png>] [-screenshot-bar] [-measure] | -print-key"
// The window before the first frame, and the share of the monitor that the first frame may fill.
WINDOW_FIRST_SIZE :: [2]int{1280, 800}
MONITOR_SHARE :: 0.9
// The hexadecimal digits of the key of the machine that name it: the head that the bar of modus shows for a viewer.
MACHINE_NAME_BYTES :: 4

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

// A toast that the next build shows: the hook of the input runs before the build, where the toolkit takes no toast.
Toast_Due :: enum u8 {
	None,
	Released,
	Held,
}

App :: struct {
	shared:             host.Shared,
	main:               host.Host,
	started:            time.Tick,
	key:                Viewer_Key,
	key_worker:         ^thread.Thread,
	// The form.
	allow_line:         ui.Line_Edit,
	address:            ui.Line_Edit,
	machine_key:        ui.Line_Edit,
	input:              bool,
	connect_at_start:   bool,
	form_problem:       Form_Problem,
	// The session that Retry starts again.
	has_retry:          bool,
	retry_host:         string, // Owned.
	retry_port:         u16,
	retry_machine_key:  [32]u8,
	retry_input:        bool,
	machine_name:       string, // Owned: "machine 3b0a9b25".
	end_sentence:       string, // The sentence of the last end: owned.
	// The session.
	viewer_connection:  ^connection.Connection,
	connected:          bool,
	end_asked:          bool,
	texture:            render.Texture,
	texture_screen:     protocol.Screen,
	screen:             protocol.Screen,
	pointer:            protocol.Pointer_Place_Body,
	frames:             u64,
	frames_drawn:       u64,
	round_trip_microseconds: u64,
	lost:               bool,
	window_sized:       bool, // The first whole frame gave the window its size.
	// The screen in the window.
	area:               layout.Rect,
	placement:          layout.Placement,
	scale_mode:         layout.Scale_Mode,
	pan_pointer:        [2]f32,
	arrow_texture:      render.Texture,
	arrow_size:         int,
	// The bar.
	hover:              layout.Hover,
	bar_forced:         bool, // -screenshot-bar.
	bar_rect:           layout.Rect,
	dot_color:          draw.Color,
	toast_due:          Toast_Due,
	// The input: the host pointer seen in every event, and what waits in the batch.
	input_held:         bool,
	host_pointer:       [2]f32,
	host_pointer_valid: bool,
	host_buttons_down:  bool,
	ctrl_down:          bool,
	alt_down:           bool,
	pending_key:        protocol.Key_Body,
	has_pending_key:    bool,
	pending_release:    bool, // A key that the toolkit does not name has no release event: the release goes with the press.
	pending_motion:     protocol.Pointer_Body,
	has_pending_motion: bool,
	pointer_buttons:    u32,
	wheel_rest:         f32,
	// A run with no window, its screenshot, and its measures.
	headless:           bool,
	screenshot:         Screenshot,
	screen_drawn:       bool, // A frame drew a whole screen of the machine: the first viewer frame of a session is whole.
	measure:            Measure,
}

main :: proc() {
	app := new(App)
	defer free(app)
	app.started = time.tick_now()
	address_argument, key_argument := "", ""
	for argument in os.args[1:] {
		switch {
		case strings.has_prefix(argument, "-address:"):
			address_argument = argument[len("-address:"):]
		case strings.has_prefix(argument, "-machine-key:"):
			key_argument = argument[len("-machine-key:"):]
		case argument == "-input":
			app.input = true
		case argument == "-headless":
			app.headless = true
		case strings.has_prefix(argument, "-screenshot:") && len(argument) > len("-screenshot:"):
			delete(app.screenshot.path)
			app.screenshot.path = strings.clone(argument[len("-screenshot:"):])
			app.screenshot.phase = .Waiting
		case argument == "-screenshot-bar":
			app.bar_forced = true
		case argument == "-measure":
			app.measure.enabled = true
		case argument == "-print-key" && len(os.args) == 2:
			os.exit(viewer_key_print())
		case:
			fmt.eprintln(USAGE)
			os.exit(2)
		}
	}
	app.connect_at_start = address_argument != "" && key_argument != ""
	if app.screenshot.phase != .Off && !app.connect_at_start {
		fmt.eprintln("modus-viewer: -screenshot needs -address and -machine-key: the screenshot is of a session that starts with the viewer")
		os.exit(2)
	}
	if app.bar_forced && app.screenshot.phase == .Off {
		fmt.eprintln("modus-viewer: -screenshot-bar goes with -screenshot: it shows the bar in the picture")
		os.exit(2)
	}
	// The viewer key and each connection need the generator of the operating system: with none, the viewer stops now.
	probe: [32]u8
	if !connection.system_random_fill(probe[:]) {
		fmt.eprintln("modus-viewer: the generator of the operating system gave no random bytes: the viewer cannot make its key or a connection, and stops")
		os.exit(1)
	}
	connection.erase_secret_bytes(&probe, size_of(probe))

	// With -headless, the window is drawn into a picture by the software renderer, and no window opens on the desktop.
	// Its renderer has the size of its opening: the reference screen of modus, the largest screen of the protocol, so the
	// screen of the machine only shrinks it.
	size := app.headless ? [2]int{protocol.SCREEN_WIDTH_LIMIT, protocol.SCREEN_HEIGHT_LIMIT} : WINDOW_FIRST_SIZE
	if !host.host_open(&app.main, &app.shared, {title = WINDOW_TITLE, size = size, headless = app.headless}, build, app) {
		os.exit(1)
	}
	app.main.input = input_hook
	app.main.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	platform.set_dark_title(app.main.win, true)
	ui.line_edit_set(&app.address, address_argument)
	ui.line_edit_set(&app.machine_key, key_argument)
	viewer_key_load_start(app)

	if !app.headless {
		platform.show_window(app.main.win)
	}
	app.screenshot.started = time.tick_now()
	for !platform.is_closed(app.main.win) && !screenshot_finished(&app.screenshot) {
		if app.screenshot.phase == .Off {
			host.hosts_wait({&app.main})
		} else if app.main.settle == 0 {
			// A post wakes the wait at once; the period only lets the loop check the hang bound of the screenshot.
			platform.wait_event(app.main.win, SCREENSHOT_CHECK_PERIOD_MILLISECONDS)
		}
		host.host_frame(&app.main)
		screenshot_step(app)
	}
	exit_code := app.screenshot.phase == .Failed ? 1 : 0

	// The window is gone: the end of the connection and the worker can be waited for.
	if app.viewer_connection != nil {
		p := connection.picture_lock(app.viewer_connection)
		measure_take_round_trips(&app.measure, p)
		connection.picture_unlock(app.viewer_connection)
		connection.connection_end_and_wait(app.viewer_connection)
		app.viewer_connection = nil
	}
	thread.join(app.key_worker)
	thread.destroy(app.key_worker)
	// The posts that wait free what they carry; none may start a connection now.
	app.connect_at_start = false
	_ = ui.drain_posts(&app.main.state)
	measure_print(&app.measure)
	for texture in ([]render.Texture{app.texture, app.arrow_texture}) {
		if texture != 0 {
			render.destroy_texture(&app.shared.r, texture)
		}
	}
	ui.line_edit_destroy(&app.allow_line)
	ui.line_edit_destroy(&app.address)
	ui.line_edit_destroy(&app.machine_key)
	delete(app.end_sentence)
	delete(app.retry_host)
	delete(app.machine_name)
	screenshot_destroy(&app.screenshot)
	host.host_close(&app.main)
	if exit_code != 0 {
		os.exit(exit_code)
	}
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
// The session

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
	delete(app.retry_host)
	app.retry_host = strings.clone(host_name)
	app.retry_port, app.retry_machine_key, app.retry_input = port, machine_key, app.input
	app.has_retry = true
	session_start(app)
}

// session_start starts the session that Retry names: the address, the machine key and the input of the last Connect.
session_start :: proc(app: ^App) {
	delete(app.end_sentence)
	app.end_sentence = ""
	delete(app.machine_name)
	app.machine_name = fmt.aprintf("machine %s", hex_of(app.retry_machine_key[:MACHINE_NAME_BYTES]))
	platform.set_title(app.main.win, app.machine_name)
	app.connected = false
	app.end_asked = false
	app.screen = {}
	app.pointer = {}
	app.frames = 0
	app.frames_drawn = 0
	app.placement = {}
	app.screen_drawn = false
	app.round_trip_microseconds = 0
	app.lost = false
	app.hover = {}
	app.has_pending_key = false
	app.has_pending_motion = false
	app.pointer_buttons = 0
	app.wheel_rest = 0
	app.input_held = app.retry_input
	settings := connection.Settings {
		host               = app.retry_host,
		port               = app.retry_port,
		machine_key        = app.retry_machine_key,
		viewer_private_key = app.key.private_key,
		input              = app.retry_input,
	}
	app.viewer_connection = connection.connection_start(settings, connection_wake, app)
}

session_retry :: proc(app: ^App) {
	if app.has_retry && app.viewer_connection == nil {
		session_start(app)
	}
}

// session_forget goes back to the form: the address can change.
session_forget :: proc(app: ^App) {
	app.has_retry = false
	delete(app.end_sentence)
	app.end_sentence = ""
	platform.set_title(app.main.win, WINDOW_TITLE)
}

// connection_end_asked closes the session at the request of the user: the end comes back as a post.
connection_end_asked :: proc(app: ^App) {
	if app.viewer_connection != nil {
		connection.connection_end(app.viewer_connection)
	}
}

// connection_wake runs on the thread of the connection: it only posts to the window.
connection_wake :: proc(user: rawptr) {
	app := (^App)(user)
	// false: the window is gone, and the exit of the program waits for this thread.
	_ = ui.post(&app.main.state, connection_changed, app)
}

// connection_changed runs on the interface thread: it uploads the damage, takes the pointer, the quality and the end.
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
		// A mip chain: a screen drawn under 1:1 is filtered from it, not sampled from its full size.
		app.texture = render.create_texture_rgba(r, width, height, mips = true)
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
	measure_taken(&app.measure, app.frames, p.frames)
	app.screen, app.pointer, app.frames, app.connected = p.screen, p.pointer, p.frames, p.connected
	app.round_trip_microseconds, app.lost = p.round_trip_microseconds, p.lost
	ended, end := p.ended, p.end
	if ended {
		measure_take_round_trips(&app.measure, p)
	}
	connection.picture_unlock(c)
	if !app.window_sized && app.frames >= 1 && app.screen.width != 0 {
		window_size_to_screen(app)
	}
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

// window_size_to_screen gives the window the size of the screen of the machine at its first whole frame: 1:1 when it
// fits in a share of the monitor, else the largest size with its proportions. A window in full screen keeps its size.
window_size_to_screen :: proc(app: ^App) {
	app.window_sized = true
	win := app.main.win
	if platform.is_fullscreen(win) {
		return
	}
	if app.headless {
		platform.set_size(win, {int(app.screen.width), int(app.screen.height)})
		return
	}
	monitor := platform.monitor_size(win)
	room := [2]int{int(f32(monitor.x) * MONITOR_SHARE), int(f32(monitor.y) * MONITOR_SHARE)}
	pixels := layout.first_window_size(app.screen.width, app.screen.height, room)
	// set_size takes logical pixels; a pixel of the machine is a pixel of the host.
	scale := max(win.dpi_scale, 1e-3)
	platform.set_size(win, {int(f32(pixels.x) / scale + 0.5), int(f32(pixels.y) / scale + 0.5)})
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
