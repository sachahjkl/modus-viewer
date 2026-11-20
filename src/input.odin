package modus_viewer

// The input of the user to the machine (src/md/features/interface.md, "The input"; src/md/features/immediacy.md, "The
// input path"). The hook of the window reads each batch of events once for each frame of the host: it keeps the last
// motion of the batch only, and sends every button, wheel and key in order, after the motion before it.

import "gt:platform"
import host "gt:host"
import protocol "modus:contract/remote_display"
import "connection"
import "layout"

// What a toast says after Ctrl+Alt.
INPUT_RELEASED_TOAST :: "Input released — Ctrl+Alt to give it back"
INPUT_HELD_TOAST :: "Input given to the machine — Ctrl+Alt to take it back"

// input_hook sends the events that the machine holds, and gives the rest to the interface.
input_hook :: proc(h: ^host.Host, events: []platform.Event) -> []platform.Event {
	app := (^App)(h.user)
	for event in events {
		pointer_note(app, event)
	}
	c := app.viewer_connection
	if c == nil || !app.connected || app.end_asked || view_state(app) != .Screen {
		return events
	}
	kept := make([dynamic]platform.Event, 0, len(events), context.temp_allocator)
	for event in events {
		if shortcut_take(app, c, event) {
			continue
		}
		if !app.input_held || !input_take(app, c, event) {
			append(&kept, event)
		}
	}
	// The motion of the batch before a key that waits for its character: a key that waits came after every motion.
	motion_flush(app, c)
	pending_flush(app, c)
	return kept[:]
}

// pointer_note keeps the place of the host pointer from every event, whoever takes it: the bar and the movement of a
// screen larger than the window read it.
pointer_note :: proc(app: ^App, event: platform.Event) {
	#partial switch event.kind {
	case .Mouse_Move, .Mouse_Press, .Mouse_Release, .Scroll:
		app.host_pointer = event.pos
		app.host_pointer_valid = true
		app.host_buttons_down = event.buttons != {}
	case .Mouse_Leave:
		app.host_pointer_valid = false
		app.host_buttons_down = false
	case .Key_Press:
		if event.key == .Ctrl {
			app.ctrl_down = true
		} else if event.key == .Alt {
			app.alt_down = true
		}
	case .Key_Release:
		if event.key == .Ctrl {
			app.ctrl_down = false
		} else if event.key == .Alt {
			app.alt_down = false
		}
	}
}

// shortcut_take switches the input on Ctrl+Alt, and says if it took the event. Its press never reaches the machine;
// the releases of Ctrl and Alt go, so no modifier stays down there.
shortcut_take :: proc(app: ^App, c: ^connection.Connection, event: platform.Event) -> bool {
	if event.kind != .Key_Press || event.repeat {
		return false
	}
	ctrl_alt := (event.key == .Ctrl && app.alt_down) || (event.key == .Alt && app.ctrl_down)
	if !ctrl_alt {
		return false
	}
	if app.input_held {
		motion_flush(app, c)
		pending_flush(app, c)
		connection.connection_input(c, protocol.Key_Body{code = scan_code_of_key(.Ctrl)})
		connection.connection_input(c, protocol.Key_Body{code = scan_code_of_key(.Alt)})
	}
	input_hold(app, !app.input_held)
	app.toast_due = app.input_held ? Toast_Due.Held : Toast_Due.Released
	return true
}

// input_hold gives the input to the machine or takes it back: the shortcut and the switch of the bar.
input_hold :: proc(app: ^App, held: bool) {
	app.input_held = held
	app.pointer_buttons = 0
	app.has_pending_motion = false
	app.has_pending_key = false
	if app.viewer_connection != nil {
		connection.connection_hold_input(app.viewer_connection, held)
	}
}

// input_take sends one event to the machine, and says if the machine took it.
input_take :: proc(app: ^App, c: ^connection.Connection, event: platform.Event) -> bool {
	#partial switch event.kind {
	case .Key_Press:
		motion_flush(app, c)
		pending_flush(app, c)
		code := event.key != .None ? scan_code_of_key(event.key) : scan_code_of_character(event.char)
		if code != 0 {
			app.pending_key = {code = code, pressed = 1, modifiers = modifiers_of(event.mods)}
			app.has_pending_key = true
			app.pending_release = event.key == .None
		}
		return true
	case .Key_Release:
		motion_flush(app, c)
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
			motion_flush(app, c)
			connection.connection_input(c, protocol.Key_Body{code = code, character = character, pressed = 1})
			connection.connection_input(c, protocol.Key_Body{code = code})
		}
		return true
	case .Mouse_Move:
		x, y, inside := screen_place(app, event.pos)
		if !machine_takes_pointer(app, event.pos, inside) {
			return false
		}
		pending_flush(app, c)
		// Only the newest place of the batch goes: one motion for each frame of the host.
		app.pending_motion = {x = x, y = y, buttons = app.pointer_buttons}
		app.has_pending_motion = true
		return true
	case .Mouse_Press, .Mouse_Release:
		x, y, inside := screen_place(app, event.pos)
		if !machine_takes_pointer(app, event.pos, inside) {
			return false
		}
		// The machine sees the press at the place where it happened: the motion before it goes first.
		pending_flush(app, c)
		motion_flush(app, c)
		app.pointer_buttons = buttons_of(event.buttons)
		connection.connection_input(c, protocol.Pointer_Body{x = x, y = y, buttons = app.pointer_buttons})
		return true
	case .Scroll:
		x, y, inside := screen_place(app, event.pos)
		if !inside || bar_holds_pointer(app, event.pos) {
			return false
		}
		pending_flush(app, c)
		motion_flush(app, c)
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

// machine_takes_pointer: the pointer is over the screen and not on the bar, or a drag that started on the screen goes
// on until its release.
machine_takes_pointer :: proc(app: ^App, at: [2]f32, inside: bool) -> bool {
	if app.pointer_buttons != 0 {
		return true
	}
	return inside && !bar_holds_pointer(app, at)
}

// bar_holds_pointer: the bar is drawn and the place is on it.
bar_holds_pointer :: proc(app: ^App, at: [2]f32) -> bool {
	if !bar_shown(app) {
		return false
	}
	r := app.bar_rect
	return at.x >= r.min.x && at.x < r.max.x && at.y >= r.min.y && at.y < r.max.y
}

// motion_flush sends the motion of the batch that waits.
motion_flush :: proc(app: ^App, c: ^connection.Connection) {
	if !app.has_pending_motion {
		return
	}
	app.has_pending_motion = false
	connection.connection_input(c, app.pending_motion)
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
screen_place :: proc(app: ^App, at: [2]f32) -> (x, y: u32, inside: bool) {
	return layout.screen_pixel(app.placement, app.area, at, app.screen.width, app.screen.height)
}
