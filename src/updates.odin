package modus_viewer

// Updates (src/md/features/program.md): gui_toolkit's Updater (gt:update) checks the viewer's latest release a while
// after the start and then every day, downloads the file that it names, checks it against its signed manifest
// (src/update: the viewer's product and key) and puts it in place of this one; the new viewer runs at the next start.
// Only an installed copy does it by itself (update.auto); a build, or a copy from the Nix store, is updated when the
// settings' Check now asks, or by Nix.

import "core:strings"
import host "gt:host"
import "gt:platform"
import prefs_page "gt:prefs_page"
import process "gt:process"
import "gt:ui"
import update "gt:update"
import viewer_update "update"

updates_start :: proc(app: ^App) {
	prefs_page.updates_start(&app.updates, {
		product = viewer_update.PRODUCT, repository = REPOSITORY, version = APP_VERSION,
		prefs = &app.prefs, state = &app.main.state, window = app.main.win,
	})
}

updates_stop :: proc(app: ^App) {
	prefs_page.updates_stop(&app.updates)
}

// At each turn of the loop: what changed is said once, where general.messages says.
updates_follow :: proc(app: ^App) {
	changed, st := prefs_page.updates_follow(&app.updates)
	if !changed {
		return
	}
	host.host_settle(&app.main)
	if words, bad := update.notice(st); words != "" {
		ui.announce(&app.announcer, bad ? .Bad : .Good, words)
	}
}

// The viewer starts again once this one has ended: an update in place, or Restart asked.
app_restart :: proc(app: ^App) {
	delete(app.launch_after)
	app.launch_after = strings.clone(process.executable_path())
	platform.request_close(app.main.win)
}
