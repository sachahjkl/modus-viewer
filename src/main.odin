// modus viewer: the screen of a modus machine in a window, and the keys and the pointer of the user to it
// (src/md/README.md, src/md/features/interface.md, src/md/features/program.md).
package modus_viewer

import "core:encoding/hex"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:thread"
import "core:time"
import config "gt:config"
import crash_bar "gt:crash_bar"
import "gt:draw"
import "gt:font"
import host "gt:host"
import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:render"
import setup "gt:setup"
import "gt:ui"
import protocol "modus:contract/remote_display"
import "connection"
import "layout"

APP_NAME :: "modus-viewer"
// The name that a person reads: the window, the settings, the texts. APP_NAME stays the technical name.
APP_TITLE :: "modus viewer"
// The folder of the viewer's files (its key, its preferences, its log): its name alone, as the first copies kept their
// key there.
APP_FOLDER :: APP_NAME
APP_VERSION :: "0.0.0"
REPOSITORY :: "sachahjkl/modus-viewer"
REPOSITORY_URL :: "https://github.com/" + REPOSITORY
USAGE :: `modus-viewer: see and drive the screen of a distant machine

  modus-viewer                                  the window: a form, then the screen of the machine
  modus-viewer -address:<host>:<port> -machine-key:<64 hexadecimal digits> [-input]
                                                the window, connected at its start
  modus-viewer ... -headless -screenshot:<file.png> [-screenshot-bar]
                                                no window: the picture of the window once the first whole screen
                                                is drawn, then the end
  modus-viewer ... -measure                     the round trip, the frame intervals and the dropped frames at the end
  modus-viewer -print-key                       the public key of the viewer key, for an allow on the machine
  modus-viewer prefs                            every preference, its value and what it does
  modus-viewer set <name> <value>               change a preference (saved)
  --pref name=value                             a preference for this run only
`
// The window before the first frame, and the share of the monitor that the first frame may fill.
WINDOW_FIRST_SIZE :: [2]int{1280, 800}
MONITOR_SHARE :: 0.9
// The hexadecimal digits of the key of the machine that name it: the head that the bar of modus shows for a viewer.
MACHINE_NAME_BYTES :: 4

// The program's catalogues of the languages that it speaks besides English (i18n/<language>.txt, written by the i18n
// command of the tool).
PROGRAM_CATALOGUES :: []i18n.Catalog{{"fr", #load("../i18n/fr.txt", string)}}

// Why the form does not start a connection.
Form_Problem :: enum u8 {
	None,
	Address_Empty,
	Port_Out_Of_Range,
	Machine_Key_Not_Hexadecimal,
	Viewer_Key_Not_Ready,
}

// The sentence of each problem, in English: tr where it is shown.
FORM_PROBLEM_SENTENCES := [Form_Problem]string {
	.None                        = "",
	.Address_Empty               = i18n.later("Give the address of the machine: a name or an IPv4 address, then :port if it is not 7101."),
	.Port_Out_Of_Range           = i18n.later("The port is a number from 1 to 65535."),
	.Machine_Key_Not_Hexadecimal = i18n.later("The machine key is 64 hexadecimal digits: the key that remote_display writes on the log of the machine."),
	.Viewer_Key_Not_Ready        = i18n.later("The viewer has no key yet: the sentence under its line says why."),
}

// A toast that the next build says: the hook of the input runs before the build, where the toolkit takes no toast.
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
	// The program (program.md): the preferences, the settings, the updates, the crash of the last run, the window's place.
	prefs:              config.Prefs,
	prefs_writer:       config.User_Writer,
	prefs_path:         string, // Owned: the file at the foot of the settings.
	standard:           prefs_page.Standard_Watch,
	settings:           Settings,
	settings_open:      bool,
	settings_page:      prefs_page.Page,
	announcer:          ui.Announcer,
	placement:          prefs_page.Placement_Keeper,
	placement_kept:     bool, // The window came back at its kept place: the first frame does not size it.
	updates:            prefs_page.Updates,
	theme_shown:        ui.Theme_Shown,
	crash_bar:          crash_bar.Bar,
	launch_after:       string, // Owned: this program again after an update, started once this one has ended.
	quiet:              bool,   // A run with no window (-headless): it reads the preferences, and writes no file.
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
	recent_noted:       bool, // The first whole frame put this machine first in the form's list.
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
	placement_of_screen: layout.Placement,
	scale_mode:         layout.Scale_Mode,
	pan_pointer:        [2]f32,
	arrow_texture:      render.Texture,
	arrow_size:         int,
	// The bar (bar.odin).
	bar:                Bar_State,
	dot_color:          draw.Color,
	toast_due:          Toast_Due,
	// The input: the host pointer seen in every event, and what waits in the batch.
	input_held:         bool,
	host_pointer:       [2]f32,
	host_pointer_valid: bool,
	host_buttons_down:  bool,
	keys_down:          platform.Keys, // The modifier keys down, for the shortcut of the input.
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
	os.exit(run(os.args[1:]))
}

run :: proc(arguments: []string) -> int {
	app := new(App)
	defer free(app)
	app.started = time.tick_now()
	address_argument, key_argument := "", ""
	rest_arguments := make([dynamic]string, context.temp_allocator)
	for index := 0; index < len(arguments); index += 1 {
		argument := arguments[index]
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
			app.bar.forced = true
		case argument == "-measure":
			app.measure.enabled = true
		case argument == "-print-key" && len(arguments) == 1:
			return viewer_key_print()
		case argument == "help", argument == "-h", argument == "--help":
			fmt.print(USAGE)
			return 0
		case argument == "--version", argument == "version":
			fmt.printfln("%s %s", APP_NAME, APP_VERSION)
			return 0
		case argument == "--pref" && index + 1 < len(arguments):
			append(&rest_arguments, argument, arguments[index + 1])
			index += 1
		case argument == "prefs", argument == "set":
			append(&rest_arguments, ..arguments[index:])
			index = len(arguments)
		case:
			fmt.eprint(USAGE)
			return 2
		}
	}
	prefs: config.Prefs
	words, problems := prefs_open(&prefs, rest_arguments[:])
	defer config.prefs_destroy(&prefs)
	for problem in problems {
		fmt.eprintfln("%s: %s", APP_NAME, problem)
	}
	if len(words) > 0 {
		return prefs_command(&prefs, words[:])
	}
	app.connect_at_start = address_argument != "" && key_argument != ""
	if app.screenshot.phase != .Off && !app.connect_at_start {
		fmt.eprintln("modus-viewer: -screenshot needs -address and -machine-key: the screenshot is of a session that starts with the viewer")
		return 2
	}
	if app.bar.forced && app.screenshot.phase == .Off {
		fmt.eprintln("modus-viewer: -screenshot-bar goes with -screenshot: it shows the bar in the picture")
		return 2
	}
	// The viewer key and each connection need the generator of the operating system: with none, the viewer stops now.
	probe: [32]u8
	if !connection.system_random_fill(probe[:]) {
		fmt.eprintln("modus-viewer: the generator of the operating system gave no random bytes: the viewer cannot make its key or a connection, and stops")
		return 1
	}
	connection.erase_secret_bytes(&probe, size_of(probe))
	app.quiet = app.headless
	if app.quiet {
		return app_run(app, &prefs, address_argument, key_argument)
	}
	// The log and the reports of a crash, before any thread and any window (gt:host program_start).
	p := host.program_start({name = APP_NAME, folder = APP_FOLDER, version = APP_VERSION})
	defer host.program_end(&p)
	context.logger = p.logger
	if p.last_crash != "" {
		crash_bar.init(&app.crash_bar, p.last_crash)
	}
	return app_run(app, &prefs, address_argument, key_argument)
}

// app_run takes the registry: it is the App's from now on (`prefs` is left empty).
app_run :: proc(app: ^App, prefs: ^config.Prefs, address_argument, key_argument: string) -> int {
	app.prefs = prefs^
	prefs^ = {}
	app.settings = prefs_read(&app.prefs)
	app.scale_mode = app.settings.scale
	// general.language is in the registry, and nothing is shown yet: every text from here on is in its language.
	prefs_page.language_start(&app.prefs, PROGRAM_CATALOGUES)
	if !app.quiet {
		config.user_writer_start(&app.prefs_writer, &app.prefs, prefs_file())
		app.prefs_path = prefs_file(context.allocator)
	}

	// With -headless, the window is drawn into a picture by the software renderer, and no window opens on the desktop.
	// Its renderer has the size of its opening: the reference screen of modus, the largest screen of the protocol, so the
	// screen of the machine only shrinks it.
	size := app.headless ? [2]int{protocol.SCREEN_WIDTH_LIMIT, protocol.SCREEN_HEIGHT_LIMIT} : WINDOW_FIRST_SIZE
	platform.set_app_id(APP_NAME)
	if !host.host_open(&app.main, &app.shared, {title = APP_TITLE, size = size, headless = app.headless, integrated_title = !app.settings.system_title}, build, app) {
		log.error("no window")
		app_free(app)
		return 1
	}
	h := &app.main
	h.input = input_hook
	h.params = app_params
	app.announcer = {mode = app.settings.messages, window = h.win, state = &h.state}
	prefs_page.standard_watch(&app.standard, &app.prefs, &h.state, {renderer = &app.shared.r, fonts = &app.shared.fonts, partial_redraw = &h.partial_redraw})
	// (Lucide: the icons of the title bar, the bar and the settings; one face, the one ui.lucide_icons gives the widgets)
	icons, _ := font.load_embedded(&app.shared.fonts, lucide.DATA)
	h.state.icon_font, h.state.lucide_font = icons, icons
	h.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	if !app.quiet {
		app.placement_kept = prefs_page.placement_restore(&app.placement, &app.prefs, h.win)
		updates_start(app)
	}
	ui.line_edit_set(&app.address, address_argument)
	ui.line_edit_set(&app.machine_key, key_argument)
	app.connect_at_start = address_argument != "" && key_argument != ""
	viewer_key_load_start(app)

	if !app.headless {
		platform.show_window(h.win)
	}
	app.screenshot.started = time.tick_now()
	for !platform.is_closed(h.win) && !screenshot_finished(&app.screenshot) {
		if app.screenshot.phase == .Off {
			if app.bar.solo_open {
				host.hosts_wait({h, &app.bar.solo})
			} else {
				host.hosts_wait({h})
			}
		} else if h.settle == 0 {
			// A post wakes the wait at once; the period only lets the loop check the hang bound of the screenshot.
			platform.wait_event(h.win, SCREENSHOT_CHECK_PERIOD_MILLISECONDS)
		}
		if !app.quiet {
			updates_follow(app)
			prefs_page.placement_track(&app.placement, &app.prefs, h.win, ui.now_ms())
			config.user_writer_save(&app.prefs_writer, &app.prefs)
			if config.user_writer_failed(&app.prefs_writer) {
				ui.announce(&app.announcer, .Bad, i18n.tr("The preferences cannot be written."))
			}
		}
		if !platform.is_closed(h.win) {
			host.host_frame(h)
		}
		solo_follow(app)
		screenshot_step(app)
	}
	exit_code := app.screenshot.phase == .Failed ? 1 : 0

	// The window is gone: the end of the connection and the worker can be waited for.
	if !app.quiet {
		prefs_page.placement_keep(&app.placement, &app.prefs, h.win)
	}
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
	_ = ui.drain_posts(&h.state)
	updates_stop(app)
	measure_print(&app.measure)
	solo_close(app)
	for texture in ([]render.Texture{app.texture, app.arrow_texture}) {
		if texture != 0 {
			render.destroy_texture(&app.shared.r, texture)
		}
	}
	host.host_close(h)
	launch := app.launch_after
	app.launch_after = ""
	app_free(app)
	if launch != "" {
		if !setup.launch(launch, nil) {
			log.errorf("%s does not start", launch)
		}
		delete(launch)
	}
	return exit_code
}

@(private = "file")
app_free :: proc(app: ^App) {
	ui.line_edit_destroy(&app.allow_line)
	ui.line_edit_destroy(&app.address)
	ui.line_edit_destroy(&app.machine_key)
	delete(app.end_sentence)
	delete(app.retry_host)
	delete(app.machine_name)
	delete(app.prefs_path)
	delete(app.launch_after)
	screenshot_destroy(&app.screenshot)
	crash_bar.destroy(&app.crash_bar)
	prefs_page.destroy(&app.settings_page)
	settings_free(&app.settings)
	prefs_page.standard_unwatch(&app.standard)
	if !app.quiet {
		config.user_writer_stop(&app.prefs_writer, &app.prefs)
	}
	prefs_page.placement_keeper_destroy(&app.placement)
	config.prefs_destroy(&app.prefs)
}

// What each build of the window is given: the theme that the settings name, light or dark as the system, the base style.
@(private = "file")
app_params :: proc(h: ^host.Host, bp: ^ui.Build_Params) {
	app := (^App)(h.user)
	// (applied only when it changes, or the system goes light or dark: a palette applied starts a cross-fade)
	choice := prefs_page.appearance_choice(app.settings.look)
	if ui.theme_show(&app.shared.theme, ui.THEMES[:], choice, &app.theme_shown, render.blend_space(&app.shared.r)) {
		platform.set_dark_title(h.win, !app.theme_shown.light)
		h.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	}
	bp.inactive = !h.win.active
	bp.base = ui.Style{pref = {.X = ui.text_size(), .Y = ui.px(28)}, font = app.shared.font, font_size = app.settings.look.font_size, text_pad = 6, cursor = .Arrow}
}

// `modus-viewer prefs` and `modus-viewer set <name> <value>`: the preferences with no window.
@(private = "file")
prefs_command :: proc(prefs: ^config.Prefs, words: []string) -> int {
	switch {
	case words[0] == "prefs" && len(words) == 1:
		for name in config.sorted_names(prefs) {
			r := config.ref_of(prefs, name)
			e := config.entry(prefs, r)
			if e.def.hidden {
				continue
			}
			fmt.printf("%s = %s%s\n    %s\n", name, config.value_string(prefs, r), config.is_default(prefs, r) ? "" : "   (changed)", e.def.description)
		}
		return 0
	case words[0] == "set" && len(words) == 3:
		if problem := config.set_from_string(prefs, words[1], words[2], .User); problem != .None {
			fmt.eprintfln("%s: %s: %s", APP_NAME, words[1], config.set_error_text(problem))
			return 1
		}
		if !config.save_user(prefs, prefs_file()) {
			fmt.eprintfln("%s: %s cannot be written", APP_NAME, prefs_file())
			return 1
		}
		return 0
	}
	fmt.eprint(USAGE)
	return 2
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

// about says what the viewer is, where general.messages says (classeur's form).
about :: proc(app: ^App) {
	ui.announce(&app.announcer, .Info, fmt.tprintf(i18n.tr("%s %s, on gui_toolkit %s. %s"), APP_TITLE, APP_VERSION, ui.VERSION, REPOSITORY_URL), in_window = true)
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

// form_recent fills the form with a machine of the list, and connects.
form_recent :: proc(app: ^App, machine: Recent_Machine) {
	ui.line_edit_set(&app.address, machine.address)
	ui.line_edit_set(&app.machine_key, machine.machine_key)
	form_connect(app)
}

// session_start starts the session that Retry names: the address, the machine key and the input of the last Connect.
session_start :: proc(app: ^App) {
	delete(app.end_sentence)
	app.end_sentence = ""
	delete(app.machine_name)
	app.machine_name = fmt.aprintf(i18n.tr("machine %s"), hex_of(app.retry_machine_key[:MACHINE_NAME_BYTES]))
	platform.set_title(app.main.win, app.machine_name)
	app.settings_open = false
	app.connected = false
	app.end_asked = false
	app.recent_noted = false
	app.screen = {}
	app.pointer = {}
	app.frames = 0
	app.frames_drawn = 0
	app.placement_of_screen = {}
	app.screen_drawn = false
	app.round_trip_microseconds = 0
	app.lost = false
	app.bar.hover = {}
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
	platform.set_title(app.main.win, APP_TITLE)
}

// connection_end_asked closes the session at the request of the user: the end comes back as a post.
connection_end_asked :: proc(app: ^App) {
	app.end_asked = true
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
	if app.frames >= 1 && app.screen.width != 0 {
		if !app.window_sized {
			window_size_to_screen(app)
		}
		// The machine showed its screen: the form offers it again from now on.
		if !app.recent_noted && !app.quiet {
			app.recent_noted = true
			recent_note(&app.prefs, fmt.tprintf("%s:%d", app.retry_host, app.retry_port), hex_of(app.retry_machine_key[:]))
		}
	}
	if ended {
		connection.connection_destroy(c)
		app.viewer_connection = nil
		app.end_sentence = end_sentence(end)
		if app.texture != 0 {
			render.destroy_texture(r, app.texture)
			app.texture, app.texture_screen = 0, {}
		}
	}
	host.host_settle(&app.main)
}

// window_size_to_screen gives the window the size of the screen of the machine at its first whole frame: 1:1 when it
// fits in a share of the monitor, else the largest size with its proportions. A window in full screen, or at the place
// that the settings kept, keeps its size.
window_size_to_screen :: proc(app: ^App) {
	app.window_sized = true
	win := app.main.win
	if platform.is_fullscreen(win) || app.placement_kept {
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
