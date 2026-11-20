package modus_viewer

// The preferences (src/md/features/settings.md): one registry of gt:config. The look, the text, the window, the
// scrolling, the input, the delays, the rendering, the updates and the language are the toolkit's standard settings
// (prefs_page.standard_register), as in every program of the owner; the viewer adds its own after them, in the group
// "viewer". The user's file is <config>/modus-viewer/prefs; `--pref name=value` overrides it for one run.

import "core:strings"
import config "gt:config"
import i18n "gt:i18n"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"
import "layout"

SCALE_PREF :: "viewer.scale"
INPUT_SHORTCUT_PREF :: "viewer.input_shortcut"
BAR_PLACE_PREF :: "viewer.bar.place"
BAR_PINNED_PREF :: "viewer.bar.pinned"
RECENT_PREF :: "viewer.recent"
// The machines that the form offers again: the last ones that showed their screen.
RECENT_LIMIT :: 5

@(rodata)
SCALE_CHOICES := [?]string{"fit", "one_to_one"}
SCALE_LABELS := [?]string{i18n.later("Fit"), i18n.later("1:1")}
@(rodata)
SHORTCUT_CHOICES := [?]string{"ctrl+alt", "ctrl+shift", "alt+shift"}
@(rodata)
SHORTCUT_LABELS := [?]string{"Ctrl+Alt", "Ctrl+Shift", "Alt+Shift"}

// The viewer's own preferences. Their words are registered in English, before the language is known: the settings page
// translates them where it shows them.
PREF_DEFS := [?]config.Def {
	{name = SCALE_PREF, title = i18n.later("Scale of the screen"), description = i18n.later("Fit: 1:1 when the screen of the machine fits the window, else as large as it fits. 1:1: always one pixel of the machine for one pixel of this screen; a larger screen moves with the pointer."), kind = .String, default = {s = "fit"}, choices = SCALE_CHOICES[:], choice_labels = SCALE_LABELS[:], tags = {"zoom", "size", "pixels"}},
	{name = INPUT_SHORTCUT_PREF, title = i18n.later("Shortcut of the input"), description = i18n.later("The keys that give the keyboard and the pointer to the machine, and take them back."), kind = .String, default = {s = "ctrl+alt"}, choices = SHORTCUT_CHOICES[:], choice_labels = SHORTCUT_LABELS[:], tags = {"keyboard", "release", "grab"}},
	{name = BAR_PINNED_PREF, title = i18n.later("Keep the bar shown"), description = i18n.later("The bar of the machine stays shown over the screen. Off: it shows when the pointer rests at its edge."), kind = .Bool, default = {b = false}, tags = {"pin", "toolbar"}},
	{name = BAR_PLACE_PREF, description = "Where the bar is: docked to an edge, floating, or in a window of its own.", kind = .String, default = {s = "top 0.500"}, hidden = true},
	{name = RECENT_PREF, description = "The last machines whose screen showed: an address and a machine key each.", kind = .String, default = {s = ""}, hidden = true},
}

// The values that the program reads, copied out of the registry (prefs_read).
Settings :: struct {
	look:         prefs_page.Appearance, // appearance.theme, mode, finish, glow, font_size
	system_title: bool,                  // window.system_title
	messages:     ui.Announce_Mode,      // general.messages: where the toasts are said
	scale:        layout.Scale_Mode,
	shortcut:     platform.Keys,         // the modifier keys that switch the input, pressed together
	bar_place:    layout.Bar_Place,
	bar_pinned:   bool,
}

// A machine of the form's list: what Connect was given.
Recent_Machine :: struct {
	address:     string,
	machine_key: string,
}

// The standard settings with the viewer's name; the rest is the toolkit's.
@(private = "file")
standard_defaults :: proc() -> prefs_page.Standard_Defaults {
	d := prefs_page.STANDARD_DEFAULTS
	d.app_name = APP_TITLE
	return d
}

prefs_file :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.Config, APP_FOLDER, context.temp_allocator), "/prefs"}, allocator)
}

// The registry with the user's file and `args`' --pref read in. It gives the arguments that are not preferences. A read
// at the start, before any window: no frame waits for it, as in the other programs of the owner.
prefs_open :: proc(p: ^config.Prefs, args: []string) -> (rest: [dynamic]string, problems: [dynamic]string) {
	p^ = config.prefs_make()
	prefs_page.standard_register(p, prefs_page.STANDARD_ALL, standard_defaults())
	config.register(p, PREF_DEFS[:])
	_, file_problems := config.load_file(p, prefs_file(), .User)
	rest, problems = config.apply_args(p, args, context.temp_allocator)
	append(&problems, ..file_problems[:])
	return
}

prefs_read :: proc(p: ^config.Prefs, allocator := context.allocator) -> (s: Settings) {
	s.look = prefs_page.appearance_read(p, allocator)
	s.system_title = config.bool_of(p, prefs_page.SYSTEM_TITLE_PREF)
	s.messages = prefs_page.announce_mode(p)
	s.scale = config.string_of(p, SCALE_PREF) == "one_to_one" ? .One_To_One : .Fit
	switch config.string_of(p, INPUT_SHORTCUT_PREF) {
	case "ctrl+shift":
		s.shortcut = {.Ctrl, .Shift}
	case "alt+shift":
		s.shortcut = {.Alt, .Shift}
	case:
		s.shortcut = {.Ctrl, .Alt}
	}
	place, ok := layout.bar_place_of_text(config.string_of(p, BAR_PLACE_PREF))
	s.bar_place = ok ? place : layout.BAR_PLACE_DEFAULT
	s.bar_pinned = config.bool_of(p, BAR_PINNED_PREF)
	return
}

settings_free :: proc(s: ^Settings) {
	prefs_page.appearance_destroy(&s.look)
	s^ = {}
}

// shortcut_words gives the shortcut as a person reads it: "Ctrl+Alt".
shortcut_words :: proc(p: ^config.Prefs) -> string {
	value := config.string_of(p, INPUT_SHORTCUT_PREF)
	for choice, index in SHORTCUT_CHOICES {
		if choice == value {
			return SHORTCUT_LABELS[index]
		}
	}
	return SHORTCUT_LABELS[0]
}

// recent_machines reads the list of the form: "address key" pairs, separated by commas, newest first.
recent_machines :: proc(p: ^config.Prefs, allocator := context.temp_allocator) -> []Recent_Machine {
	list := make([dynamic]Recent_Machine, allocator)
	for entry in strings.split(config.string_of(p, RECENT_PREF), ",", context.temp_allocator) {
		words := strings.fields(entry, context.temp_allocator)
		if len(words) != 2 || len(list) == RECENT_LIMIT {
			continue
		}
		_, key_ok := parse_machine_key(words[1])
		if !key_ok {
			continue
		}
		append(&list, Recent_Machine{address = words[0], machine_key = words[1]})
	}
	return list[:]
}

// recent_note puts a machine first in the list of the form, once.
recent_note :: proc(p: ^config.Prefs, address, machine_key: string) {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, address)
	strings.write_byte(&b, ' ')
	strings.write_string(&b, machine_key)
	count := 1
	for machine in recent_machines(p) {
		if machine.address == address && machine.machine_key == machine_key || count == RECENT_LIMIT {
			continue
		}
		strings.write_byte(&b, ',')
		strings.write_string(&b, machine.address)
		strings.write_byte(&b, ' ')
		strings.write_string(&b, machine.machine_key)
		count += 1
	}
	_ = config.set_string(p, RECENT_PREF, strings.to_string(b))
}

// bar_place_keep writes the place of the bar in the registry; the writer saves it off the window's thread.
bar_place_keep :: proc(app: ^App, place: layout.Bar_Place) {
	app.settings.bar_place = place
	_ = config.set_string(&app.prefs, BAR_PLACE_PREF, layout.bar_place_text(place, context.temp_allocator))
}

bar_pinned_keep :: proc(app: ^App, pinned: bool) {
	app.settings.bar_pinned = pinned
	_ = config.set_bool(&app.prefs, BAR_PINNED_PREF, pinned)
}
