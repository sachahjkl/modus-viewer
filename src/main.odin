// modus viewer: the screen of a modus machine in a window, and the keys and the pointer of the user to it
// (src/md/README.md).
package modus_viewer

import "core:fmt"

APP_NAME :: "modus-viewer"
APP_VERSION :: "0.0.0"

main :: proc() {
	fmt.printfln("%s %s", APP_NAME, APP_VERSION)
}
