package modus_viewer

// The viewer key (src/md/features/viewer_key.md): read and sealed on a worker, never on the interface thread. The
// worker posts its result to the window.

import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:thread"
import i18n "gt:i18n"
import secrets "gt:secrets"
import "gt:platform"
import "gt:ui"
import "connection"

// The name of the program for the store of secrets, and of the sealed key in it.
SECRETS_APP :: APP_NAME
SECRET_NAME :: "viewer key"
// The file of the configuration folder that holds the sealed field.
KEY_FILE_NAME :: "viewer_key"

// Where the key of this run comes from.
Viewer_Key_Origin :: enum u8 {
	Loading,          // The worker did not answer yet.
	Kept,             // The store of secrets opened the key of an earlier run.
	Made,             // No key was kept: a new key, now sealed in the store.
	Run_Only_No_Store,    // No store of secrets, or no configuration folder: a key of this run only.
	Run_Only_Not_Opened,  // A kept key exists, and the store cannot open it: a key of this run only.
	Run_Only_Not_Written, // A new key was sealed, and its file could not be written: a key of this run only.
	No_System_Random,     // The generator of the operating system gave no bytes: no key, and no connection.
}

// The sentence of each origin, in English: tr where it is shown (the command line prints the English).
VIEWER_KEY_ORIGIN_SENTENCES := [Viewer_Key_Origin]string {
	.Loading              = i18n.later("The viewer key is being read."),
	.Kept                 = "",
	.Made                 = i18n.later("This viewer made its key, and keeps it in the store of secrets of this account."),
	.Run_Only_No_Store    = i18n.later("No store of secrets answers: this key lasts until the viewer closes."),
	.Run_Only_Not_Opened  = i18n.later("The store of secrets cannot open the kept key (a locked keyring, or another account): this key lasts until the viewer closes."),
	.Run_Only_Not_Written = i18n.later("The file of the key could not be written: this key lasts until the viewer closes."),
	.No_System_Random     = i18n.later("The generator of the operating system gave no random bytes: this viewer has no key, and connects to no machine."),
}

Viewer_Key :: struct {
	origin:      Viewer_Key_Origin,
	private_key: [32]u8,
	public_key:  [32]u8,
}

// viewer_key_load_start starts the worker. Its result arrives in viewer_key_arrived, on the interface thread.
viewer_key_load_start :: proc(app: ^App) {
	worker := thread.create(viewer_key_worker)
	worker.data = app
	app.key_worker = worker
	thread.start(worker)
}

// What the worker posts: the window that asked, and the key.
@(private = "file")
Key_Arrival :: struct {
	app: ^App,
	key: Viewer_Key,
}

@(private = "file")
viewer_key_worker :: proc(t: ^thread.Thread) {
	arrival := new(Key_Arrival)
	arrival.app = (^App)(t.data)
	arrival.key = viewer_key_load()
	if !ui.post(&arrival.app.main.state, viewer_key_arrived, arrival) {
		connection.erase_secret_bytes(arrival, size_of(Key_Arrival))
		free(arrival)
	}
}

// viewer_key_arrived runs on the interface thread.
@(private = "file")
viewer_key_arrived :: proc(data: rawptr, _: u64) {
	arrival := (^Key_Arrival)(data)
	app := arrival.app
	app.key = arrival.key
	connection.erase_secret_bytes(arrival, size_of(Key_Arrival))
	free(arrival)
	app_key_ready(app)
}

// viewer_key_print is `modus-viewer -print-key`: it prints the public key of the kept viewer key, which a principal
// allows before the viewer connects, and gives the exit code. With no window, it may wait on the disk and the store.
// A key of this run only is refused: it would be gone when the viewer starts again to connect.
viewer_key_print :: proc() -> int {
	key := viewer_key_load()
	defer connection.erase_secret_bytes(&key.private_key, size_of(key.private_key))
	switch key.origin {
	case .Kept, .Made:
		fmt.println(hex_of(key.public_key[:]))
		return 0
	case .Loading, .Run_Only_No_Store, .Run_Only_Not_Opened, .Run_Only_Not_Written, .No_System_Random:
		fmt.eprintfln("modus-viewer: no kept viewer key to print: %s", VIEWER_KEY_ORIGIN_SENTENCES[key.origin])
		return 1
	}
	return 1
}

// viewer_key_load reads the sealed key, or makes one. It waits on the disk and on the store of secrets.
@(private = "file")
viewer_key_load :: proc() -> (key: Viewer_Key) {
	folder := platform.user_dir(.Config, APP_NAME, context.temp_allocator)
	path := folder == "" ? "" : concatenate_path(folder, KEY_FILE_NAME)
	if path != "" && os.exists(path) {
		field, read_error := os.read_entire_file(path, context.temp_allocator)
		if read_error != nil {
			return key_of_this_run(.Run_Only_Not_Opened)
		}
		secret, opened := secrets.open(SECRETS_APP, string(field), context.temp_allocator)
		if opened != .Opened {
			// A new key would need a new allow on each machine: the kept one stays for a later run.
			return key_of_this_run(.Run_Only_Not_Opened)
		}
		decoded, decoded_ok := hex.decode(transmute([]u8)secret, context.temp_allocator)
		if !decoded_ok || len(decoded) != 32 {
			return key_of_this_run(.Run_Only_Not_Opened)
		}
		copy(key.private_key[:], decoded)
		connection.erase_secret_bytes(raw_data(decoded), len(decoded))
		connection.erase_secret_bytes(raw_data(secret), len(secret))
		return key_finish(key, .Kept)
	}
	key = key_of_this_run(.Made)
	if key.origin == .No_System_Random {
		return key
	}
	if path == "" {
		key.origin = .Run_Only_No_Store
		return key
	}
	encoded := hex.encode(key.private_key[:], context.temp_allocator)
	field, sealed := secrets.seal(SECRETS_APP, SECRET_NAME, string(encoded), context.temp_allocator)
	connection.erase_secret_bytes(raw_data(encoded), len(encoded))
	if sealed != .Sealed {
		key.origin = .Run_Only_No_Store
		return key
	}
	if os.make_directory_all(folder) != nil || os.write_entire_file(path, transmute([]u8)field) != nil {
		secrets.forget(SECRETS_APP, field)
		key.origin = .Run_Only_Not_Written
	}
	return key
}

// key_of_this_run draws a new key from the generator of the operating system. With no bytes, there is no key.
@(private = "file")
key_of_this_run :: proc(origin: Viewer_Key_Origin) -> Viewer_Key {
	key: Viewer_Key
	if !connection.system_random_fill(key.private_key[:]) {
		connection.erase_secret_bytes(&key.private_key, size_of(key.private_key))
		return {origin = .No_System_Random}
	}
	return key_finish(key, origin)
}

@(private = "file")
key_finish :: proc(key: Viewer_Key, origin: Viewer_Key_Origin) -> Viewer_Key {
	result := key
	result.origin = origin
	result.public_key, _ = connection.public_key_of(result.private_key)
	return result
}

@(private = "file")
concatenate_path :: proc(folder, name: string) -> string {
	bytes := make([]u8, len(folder) + 1 + len(name), context.temp_allocator)
	copy(bytes, folder)
	bytes[len(folder)] = '/'
	copy(bytes[len(folder) + 1:], name)
	return string(bytes)
}
