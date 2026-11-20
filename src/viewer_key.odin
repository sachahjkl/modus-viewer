package modus_viewer

// The viewer key (src/md/features/viewer_key.md): read and sealed on a worker, never on the interface thread. The
// worker posts its result to the window.

import "core:crypto"
import "core:encoding/hex"
import "core:os"
import "core:thread"
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
}

@(rodata)
VIEWER_KEY_ORIGIN_SENTENCES := [Viewer_Key_Origin]string {
	.Loading              = "The viewer key is being read.",
	.Kept                 = "",
	.Made                 = "This viewer made its key, and keeps it in the store of secrets of this account.",
	.Run_Only_No_Store    = "No store of secrets answers: this key lasts until the viewer closes.",
	.Run_Only_Not_Opened  = "The store of secrets cannot open the kept key (a locked keyring, or another account): this key lasts until the viewer closes.",
	.Run_Only_Not_Written = "The file of the key could not be written: this key lasts until the viewer closes.",
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
		crypto.zero_explicit(arrival, size_of(Key_Arrival))
		free(arrival)
	}
}

// viewer_key_arrived runs on the interface thread.
@(private = "file")
viewer_key_arrived :: proc(data: rawptr, _: u64) {
	arrival := (^Key_Arrival)(data)
	app := arrival.app
	app.key = arrival.key
	crypto.zero_explicit(arrival, size_of(Key_Arrival))
	free(arrival)
	app_key_ready(app)
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
		crypto.zero_explicit(raw_data(decoded), len(decoded))
		crypto.zero_explicit(raw_data(secret), len(secret))
		return key_finish(key, .Kept)
	}
	key = key_of_this_run(.Made)
	if path == "" {
		key.origin = .Run_Only_No_Store
		return key
	}
	encoded := hex.encode(key.private_key[:], context.temp_allocator)
	field, sealed := secrets.seal(SECRETS_APP, SECRET_NAME, string(encoded), context.temp_allocator)
	crypto.zero_explicit(raw_data(encoded), len(encoded))
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

// key_of_this_run draws a new key from the generator of the host system.
@(private = "file")
key_of_this_run :: proc(origin: Viewer_Key_Origin) -> Viewer_Key {
	key: Viewer_Key
	crypto.rand_bytes(key.private_key[:])
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
