package connection

import "base:intrinsics"

// erase_secret_bytes writes 0 over a secret. Each byte is a volatile store, so the compiler keeps the stores of a
// buffer that is freed next. The viewer imports no crypto package: the copy of the cryptography of modus and the one of
// Odin declare packages of the same names, and one program cannot hold both.
erase_secret_bytes :: proc "contextless" (data: rawptr, count: int) {
	bytes := ([^]u8)(data)
	for index in 0 ..< count {
		intrinsics.volatile_store(&bytes[index], 0)
	}
}
