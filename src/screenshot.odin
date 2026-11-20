package modus_viewer

// The screenshot of the window (src/md/features/screenshot.md): once the first whole screen of the machine is drawn,
// the window reads its picture back, writes it as a PNG file, and the viewer ends. A condition starts the capture, not
// a time; SCREENSHOT_HANG_BOUND only ends a run that hangs.

import "core:fmt"
import "core:os"
import "core:time"
import "gt:png"
import "gt:render"

// The whole wait of a screenshot: the start of the viewer key, the handshake, the first whole frame and its read back.
// It ends a run that hangs; a run that works ends at its condition.
SCREENSHOT_HANG_BOUND :: 120 * time.Second
// The longest sleep of the loop of a screenshot between two checks of the hang bound: a post of the connection or of
// the worker wakes the loop at once.
SCREENSHOT_CHECK_PERIOD_MILLISECONDS :: 1000

// Where the screenshot is.
Screenshot_Phase :: enum u8 {
	Off,          // No -screenshot: the viewer runs as usual.
	Waiting,      // No frame drew the first whole screen of the machine yet.
	Capture_Asked, // A frame drew it, and the renderer reads the picture back.
	Written,      // The PNG file is written: the viewer ends with 0.
	Failed,       // The viewer ends with 1, and `failure` says why.
}

Screenshot :: struct {
	phase:   Screenshot_Phase,
	path:    string, // Owned.
	started: time.Tick,
	failure: string, // Owned.
}

screenshot_finished :: proc(shot: ^Screenshot) -> bool {
	return shot.phase == .Written || shot.phase == .Failed
}

// screenshot_step moves the screenshot after one frame of the window.
screenshot_step :: proc(app: ^App) {
	shot := &app.screenshot
	switch shot.phase {
	case .Off, .Written, .Failed:
		return
	case .Waiting:
		if app.screen_drawn {
			if !render.capture_request(&app.shared.r) {
				screenshot_fail(shot, "the renderer refused to read the picture back")
				return
			}
			shot.phase = .Capture_Asked
			// The next frame is the one that the renderer copies.
			app.main.settle = max(app.main.settle, 1)
		} else if app.viewer_connection == nil && app.end_sentence != "" {
			screenshot_fail(shot, app.end_sentence)
			return
		} else if app.key.origin == .No_System_Random {
			screenshot_fail(shot, VIEWER_KEY_ORIGIN_SENTENCES[.No_System_Random])
			return
		}
	case .Capture_Asked:
		pixels, size, status := render.capture_poll(&app.shared.r)
		switch status {
		case .Pending:
			// The copy is readable after a later frame.
			app.main.settle = max(app.main.settle, 1)
		case .Ready:
			defer delete(pixels)
			file := png.encode(pixels, size.x, size.y, .Small)
			defer delete(file)
			if os.write_entire_file(shot.path, file) != nil {
				screenshot_fail(shot, fmt.tprintf("the file %s cannot be written", shot.path))
				return
			}
			fmt.printfln("modus-viewer: wrote %s, %d × %d, with the screen of the machine of %d × %d", shot.path, size.x, size.y, app.screen.width, app.screen.height)
			shot.phase = .Written
			return
		case .Failed, .None:
			screenshot_fail(shot, "the renderer gave no picture of the window")
			return
		}
	}
	if time.tick_since(shot.started) > SCREENSHOT_HANG_BOUND {
		screenshot_fail(shot, fmt.tprintf("no whole screen of the machine was drawn in %v", SCREENSHOT_HANG_BOUND))
	}
}

@(private = "file")
screenshot_fail :: proc(shot: ^Screenshot, why: string) {
	shot.phase = .Failed
	shot.failure = fmt.aprint(why)
	fmt.eprintfln("modus-viewer: no screenshot: %s", why)
}

screenshot_destroy :: proc(shot: ^Screenshot) {
	delete(shot.path)
	delete(shot.failure)
	shot^ = {}
}
