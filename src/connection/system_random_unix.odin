#+build linux, darwin
package connection

import "core:os"

// system_random_fill fills out with bytes of the generator of the operating system, from /dev/urandom. false: the
// system gave fewer bytes, and the caller stops; no fixed seed ever takes their place.
system_random_fill :: proc(out: []u8) -> bool {
	file, open_error := os.open("/dev/urandom")
	if open_error != nil {
		return false
	}
	defer os.close(file)
	count, read_error := os.read_full(file, out)
	return read_error == nil && count == len(out)
}
