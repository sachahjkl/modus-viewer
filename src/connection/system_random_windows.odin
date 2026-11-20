#+build windows
package connection

import windows "core:sys/windows"

// system_random_fill fills out with bytes of the generator of the operating system, from BCryptGenRandom. false: the
// system refused, and the caller stops; no fixed seed ever takes their place.
system_random_fill :: proc(out: []u8) -> bool {
	if len(out) == 0 {
		return true
	}
	status := windows.BCryptGenRandom(nil, raw_data(out), windows.ULONG(len(out)), windows.BCRYPT_USE_SYSTEM_PREFERRED_RNG)
	return status == 0
}
