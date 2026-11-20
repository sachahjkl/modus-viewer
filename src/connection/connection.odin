// One connection to the service `remote_display` of a modus machine, on a thread of its own
// (src/md/features/connection.md). The thread owns the UDP socket, the QUIC connection and the session. The window gives
// it input through a queue, and reads what it publishes in the shared picture: neither side waits for the other but on
// the lock.
package connection

import "core:crypto"
import "core:net"
import "core:sync"
import "core:thread"
import "core:time"
import "modus:contract/errors"
import protocol "modus:contract/remote_display"
import primitives "modus:private/cryptography/cryptography_primitives"
import "modus:support/quic"
import "modus:support/random"
import "../session"

// The port of the service when the address names none.
DEFAULT_PORT :: protocol.LISTEN_PORT
// The bounds of a wait of the thread on its socket: the delay of a key while the input is on, and of a Disconnect else.
INPUT_WAIT_BOUND :: 4 * time.Millisecond
IDLE_WAIT_BOUND :: 100 * time.Millisecond
// The keys and pointer records that wait for the thread. Past it, a record of the window is dropped and counted.
INPUT_CAPACITY :: 256
// The idle timeout that the viewer asks for: the machine sends a frame only on damage, so a still screen is silent.
IDLE_TIMEOUT_MILLISECONDS :: 30_000
// The datagrams that one turn of the thread sends at most, before it reads again.
DATAGRAMS_PER_TURN :: 64

Settings :: struct {
	host:               string, // A name or an IPv4 address. The connection keeps its own copy.
	port:               u16,
	machine_key:        [32]u8, // The pinned Ed25519 public key of the service.
	viewer_private_key: [32]u8,
	input:              bool,   // The user turned the input on.
}

Input :: union {
	protocol.Key_Body,
	protocol.Pointer_Body,
}

// What the thread publishes for the window, under Connection.lock.
Picture :: struct {
	rgba:           []u8, // RGBA8, opaque, rows of screen.width pixels.
	screen:         protocol.Screen,
	screen_changed: bool, // The size changed since the window last took the picture: its texture must change too.
	damage:         [session.DAMAGE_CAPACITY]session.Rectangle,
	damage_count:   int,
	pointer:        protocol.Pointer_Place_Body,
	frames:         u64,
	connected:      bool, // The handshake completed.
	ended:          bool, // The thread ended: `end` says how. The window then calls connection_destroy.
	end:            session.End,
	input_dropped:  u64,  // Records of the window that found the queue full.
}

Connection :: struct {
	lock:            sync.Mutex,
	picture:         Picture,
	input:           [INPUT_CAPACITY]Input,
	input_count:     int,
	end_asked:       bool,
	// The thread calls it after each publication, from its own thread: it must only post to the window.
	on_change:       proc(user: rawptr),
	on_change_user:  rawptr,
	settings:        Settings,
	thread:          ^thread.Thread,
}

// connection_start starts the thread of a connection. on_change runs on that thread: it posts to the window.
connection_start :: proc(settings: Settings, on_change: proc(user: rawptr), user: rawptr) -> ^Connection {
	c := new(Connection)
	c.settings = settings
	c.settings.host = clone_string(settings.host)
	c.on_change, c.on_change_user = on_change, user
	c.picture.rgba = make([]u8, protocol.SCREEN_WIDTH_LIMIT * protocol.SCREEN_HEIGHT_LIMIT * 4)
	c.thread = thread.create(connection_thread)
	c.thread.data = c
	thread.start(c.thread)
	return c
}

// connection_destroy frees a connection whose thread ended (Picture.ended). It does not wait.
connection_destroy :: proc(c: ^Connection) {
	thread.join(c.thread)
	thread.destroy(c.thread)
	crypto.zero_explicit(&c.settings.viewer_private_key, size_of(c.settings.viewer_private_key))
	delete(c.picture.rgba)
	delete(c.settings.host)
	free(c)
}

// connection_end_and_wait asks for the end, and waits for the thread: at the exit of the program only, where the window
// is gone. The wait is at most one wait bound of the thread and one send.
connection_end_and_wait :: proc(c: ^Connection) {
	connection_end(c)
	connection_destroy(c)
}

// connection_end asks the thread to close the connection. It does not wait.
connection_end :: proc(c: ^Connection) {
	sync.mutex_lock(&c.lock)
	c.end_asked = true
	sync.mutex_unlock(&c.lock)
}

// connection_input queues a key or a pointer record for the thread. A pointer move with the same buttons replaces a move
// that still waits, so a fast mouse fills nothing.
connection_input :: proc(c: ^Connection, record: Input) {
	sync.mutex_lock(&c.lock)
	defer sync.mutex_unlock(&c.lock)
	if pointer, is_pointer := record.(protocol.Pointer_Body); is_pointer && pointer.wheel == 0 && c.input_count > 0 {
		if last, last_is_pointer := c.input[c.input_count - 1].(protocol.Pointer_Body); last_is_pointer && last.buttons == pointer.buttons && last.wheel == 0 {
			c.input[c.input_count - 1] = pointer
			return
		}
	}
	if c.input_count == INPUT_CAPACITY {
		c.picture.input_dropped += 1
		return
	}
	c.input[c.input_count] = record
	c.input_count += 1
}

// picture_lock gives the shared picture under the lock; picture_unlock gives it back.
picture_lock :: proc(c: ^Connection) -> ^Picture {
	sync.mutex_lock(&c.lock)
	return &c.picture
}

picture_unlock :: proc(c: ^Connection) {
	sync.mutex_unlock(&c.lock)
}

// public_key_of gives the Ed25519 public key of a private key, with the cryptography that the connection uses.
public_key_of :: proc(private_key: [32]u8) -> (public_key: [32]u8, ok: bool) {
	private := private_key
	secret := string(private[:])
	result := public_key[:]
	error: errors.Error_Record
	ok = primitives.ed25519_public_key(&secret, &result, &error) >= 0
	crypto.zero_explicit(&private, size_of(private))
	return public_key, ok
}

////////////////////////////////
// The thread

@(private = "file")
connection_thread :: proc(t: ^thread.Thread) {
	c := (^Connection)(t.data)
	end := connection_run(c)
	sync.mutex_lock(&c.lock)
	c.picture.ended = true
	c.picture.end = end
	sync.mutex_unlock(&c.lock)
	c.on_change(c.on_change_user)
}

// The state of the thread: one record, so that the procedures of a turn share it.
@(private = "file")
Run :: struct {
	c:                ^Connection,
	socket:           net.UDP_Socket,
	machine:          net.Endpoint,
	quic:             ^quic.Connection,
	streams:          []quic.Stream,
	configuration:    quic.Connection_Configuration,
	cryptography:     quic.Cryptography,
	generator:        random.Generator,
	session:          session.Session,
	start:            time.Tick,
	stream:           u64,
	has_stream:       bool,
	closed_by_viewer: bool,
	refused:          bool,
	connected_told:   bool,
}

@(private = "file")
connection_run :: proc(c: ^Connection) -> session.End {
	machine, resolved := resolve(c.settings.host, c.settings.port)
	if !resolved {
		return {kind = .Address_Not_Found}
	}
	socket, socket_error := net.make_bound_udp_socket(net.IP4_Any, 0)
	if socket_error != nil {
		return {kind = .No_Socket}
	}
	defer net.close(socket)

	run := new(Run)
	defer free(run)
	run.c, run.socket, run.machine = c, socket, machine
	// The record has about 88 KiB: it never goes on a stack.
	run.quic = new(quic.Connection)
	defer free(run.quic)
	run.streams = make([]quic.Stream, 1)
	defer delete(run.streams)
	run.cryptography = cryptography_of_the_host()
	seed: [random.SEED_SIZE]u8
	crypto.rand_bytes(seed[:])
	// The generator of the host system draws from the entropy of the system: at least the strength of the generator of
	// the processor, which QUIC asks for.
	if !random.generator_seed(&run.generator, &seed, .Processor) {
		return {kind = .Start_Refused}
	}
	run.configuration = {idle_timeout_milliseconds = IDLE_TIMEOUT_MILLISECONDS}
	run.configuration.tls = {role = .Client, least_seed_strength = .Processor}
	run.configuration.tls.application_protocol_length = copy(run.configuration.tls.application_protocol[:], protocol.APPLICATION_PROTOCOL)
	run.configuration.tls.server_public_key = c.settings.machine_key
	run.configuration.tls.client_private_key = c.settings.viewer_private_key
	defer crypto.zero_explicit(&run.configuration.tls.client_private_key, size_of(run.configuration.tls.client_private_key))
	session.session_init(&run.session, c.settings.input)
	defer session.session_destroy(&run.session)
	run.start = time.tick_now()

	error: errors.Error_Record
	if !quic.connection_start_client(run.quic, run.streams, &run.configuration, &run.cryptography, &run.generator, now(run), &error) {
		return {kind = .Start_Refused}
	}
	datagram: [2048]u8
	for {
		turn(run)
		if run.quic.state == .Closed {
			break
		}
		// The close of this side went out: the thread ends with no drain, so a Disconnect is at once.
		if run.quic.state == .Closing && (run.closed_by_viewer || run.refused) {
			break
		}
		at := now(run)
		deadline := quic.connection_deadline(run.quic)
		if deadline <= at {
			quic.connection_time_passes(run.quic, at)
			continue
		}
		bound := c.settings.input && run.has_stream ? INPUT_WAIT_BOUND : IDLE_WAIT_BOUND
		// In microseconds first: a connection with no timer has the largest deadline, past the range of a Duration.
		wait := time.Duration(min(deadline - at, u64(bound / time.Microsecond))) * time.Microsecond
		_ = net.set_option(socket, .Receive_Timeout, max(wait, time.Millisecond))
		count, from, receive_error := net.recv_udp(socket, datagram[:])
		if receive_error == nil && count > 0 && same_endpoint(from, machine) {
			quic.connection_datagram_receive(run.quic, datagram[:count], now(run), &error)
		}
	}
	return end_of(run)
}

// turn runs the work of one turn: the input and the end that the window asked for, the stream, the datagrams.
@(private = "file")
turn :: proc(run: ^Run) {
	c := run.c
	at := now(run)
	input: [INPUT_CAPACITY]Input
	sync.mutex_lock(&c.lock)
	input_count, end_asked := c.input_count, c.end_asked
	copy(input[:], c.input[:input_count])
	c.input_count = 0
	sync.mutex_unlock(&c.lock)

	if end_asked && !run.closed_by_viewer && !run.refused && (run.quic.state == .Handshake || run.quic.state == .Connected) {
		run.closed_by_viewer = true
		quic.connection_close(run.quic, u64(protocol.Display_Error.None), at)
	}
	if run.quic.state == .Connected {
		if !run.connected_told {
			run.connected_told = true
			sync.mutex_lock(&c.lock)
			c.picture.connected = true
			sync.mutex_unlock(&c.lock)
			c.on_change(c.on_change_user)
		}
		if !run.has_stream {
			run.stream, run.has_stream = quic.stream_open(run.quic)
		}
	}
	if run.has_stream && run.quic.state == .Connected {
		for record in input[:input_count] {
			// A refused or full record stays in the viewer: the session already checked it against the border.
			switch value in record {
			case protocol.Key_Body:
				_ = session.session_key(&run.session, value)
			case protocol.Pointer_Body:
				_ = session.session_pointer(&run.session, value)
			}
		}
		stream_write(run)
		stream_read(run, at)
		// The take of a frame that the read made whole goes in this turn.
		stream_write(run)
	}
	buffer: [quic.MAX_DATAGRAM_SIZE]u8
	for _ in 0 ..< DATAGRAMS_PER_TURN {
		length := quic.connection_datagram_send(run.quic, buffer[:], at)
		if length == 0 {
			break
		}
		_, _ = net.send_udp(run.socket, buffer[:length], run.machine)
	}
}

@(private = "file")
stream_write :: proc(run: ^Run) {
	for {
		waiting := session.session_outgoing(&run.session)
		if len(waiting) == 0 {
			return
		}
		taken := quic.stream_write(run.quic, run.stream, waiting, false)
		if taken == 0 {
			return
		}
		session.session_written(&run.session, taken)
	}
}

// stream_read gives the session the bytes of the stream, at most the rest of one record at a time.
@(private = "file")
stream_read :: proc(run: ^Run, at: u64) {
	for run.quic.state == .Connected {
		space := session.session_receive_space(&run.session)
		if space == nil {
			return
		}
		count, _, reset := quic.stream_read(run.quic, run.stream, space)
		if reset || count == 0 {
			return
		}
		switch session.session_received(&run.session, count) {
		case .Need_More, .Taken, .Screen_Size:
		case .Pointer_Moved:
			publish_pointer(run)
		case .Frame_Whole:
			publish_frame(run)
		case .Refused:
			run.refused = true
			quic.connection_close(run.quic, u64(protocol.Display_Error.Bad_Record), at)
			return
		}
	}
}

// publish_frame copies the damage of a whole viewer frame into the shared picture, as RGBA, and wakes the window.
@(private = "file")
publish_frame :: proc(run: ^Run) {
	c, s := run.c, &run.session
	width := int(s.screen.width)
	sync.mutex_lock(&c.lock)
	p := &c.picture
	if p.screen != s.screen {
		p.screen = s.screen
		p.screen_changed = true
		p.damage_count = 0
	}
	for rectangle in s.damage[:s.damage_count] {
		for row in int(rectangle.y) ..< int(rectangle.y + rectangle.height) {
			for column in int(rectangle.x) ..< int(rectangle.x + rectangle.width) {
				pixel := s.pixels[row * width + column]
				out := p.rgba[(row * width + column) * 4:][:4]
				out[0], out[1], out[2], out[3] = u8(pixel >> 16), u8(pixel >> 8), u8(pixel), 0xFF
			}
		}
		picture_damage_add(p, rectangle)
	}
	p.pointer = s.pointer
	p.frames += 1
	sync.mutex_unlock(&c.lock)
	c.on_change(c.on_change_user)
}

@(private = "file")
publish_pointer :: proc(run: ^Run) {
	c := run.c
	sync.mutex_lock(&c.lock)
	c.picture.pointer = run.session.pointer
	sync.mutex_unlock(&c.lock)
	c.on_change(c.on_change_user)
}

// picture_damage_add adds a rectangle to the damage that the window did not take yet. A new size of the screen owes the
// whole screen, which the window uploads whole anyway.
@(private = "file")
picture_damage_add :: proc(p: ^Picture, added: session.Rectangle) {
	if p.screen_changed {
		return
	}
	for index in 0 ..< p.damage_count {
		if session.rectangle_extend(&p.damage[index], added) {
			return
		}
	}
	if p.damage_count < len(p.damage) {
		p.damage[p.damage_count] = added
		p.damage_count += 1
		return
	}
	bounds := added
	for rectangle in p.damage[:p.damage_count] {
		bounds = session.rectangle_union(bounds, rectangle)
	}
	p.damage[0] = bounds
	p.damage_count = 1
}

// end_of says how the connection ended, from the record of QUIC and what the viewer did.
@(private = "file")
end_of :: proc(run: ^Run) -> session.End {
	q := run.quic
	switch {
	case run.closed_by_viewer:
		return {kind = .Closed_By_Viewer}
	case run.refused:
		return {kind = .Viewer_Refused_Record, refusal = run.session.refusal, record_problem = run.session.record_problem, screen_piece_problem = run.session.screen_piece_problem}
	case q.closed_by_handshake_timeout:
		return {kind = .No_Handshake}
	case q.closed_by_idle_timeout:
		return {kind = .Machine_Silent}
	case q.close_is_application:
		return {kind = .Machine_Code, code = q.close_error_code}
	case q.closed_by_peer && q.close_error_code == quic.CRYPTO_ERROR_BASE + u64(quic.Alert.Access_Denied):
		return {kind = .Key_Not_Allowed}
	case !q.closed_by_peer && q.close_error_code == quic.CRYPTO_ERROR_BASE + u64(quic.Alert.Bad_Certificate):
		return {kind = .Machine_Key_Differs}
	}
	return {kind = .Transport_Code, code = q.close_error_code, by_machine = q.closed_by_peer}
}

////////////////////////////////
// The host

// now is the clock of QUIC: microseconds from the start of the connection, from 1.
@(private = "file")
now :: proc(run: ^Run) -> u64 {
	return u64(time.tick_since(run.start) / time.Microsecond) + 1
}

@(private = "file")
resolve :: proc(host: string, port: u16) -> (endpoint: net.Endpoint, ok: bool) {
	if address, is_address := net.parse_ip4_address(host); is_address {
		return {address = address, port = int(port)}, true
	}
	found, error := net.resolve_ip4(host)
	if error != nil {
		return {}, false
	}
	found.port = int(port)
	return found, true
}

@(private = "file")
same_endpoint :: proc(first, second: net.Endpoint) -> bool {
	first_address, first_four := first.address.(net.IP4_Address)
	second_address, second_four := second.address.(net.IP4_Address)
	return first.port == second.port && first_four && second_four && first_address == second_address
}

@(private = "file")
clone_string :: proc(text: string) -> string {
	bytes := make([]u8, len(text))
	copy(bytes, text)
	return string(bytes)
}

// cryptography_of_the_host gives the procedures of the cryptography module of modus, compiled for the host from its
// private part, as the peer of the modus tool does.
@(private = "file")
cryptography_of_the_host :: proc() -> quic.Cryptography {
	return {
		seal_with_aes_128_gcm                = primitives.seal_with_aes_128_gcm,
		open_with_aes_128_gcm                = primitives.open_with_aes_128_gcm,
		seal_with_chacha20_poly1305          = primitives.seal_with_chacha20_poly1305,
		open_with_chacha20_poly1305          = primitives.open_with_chacha20_poly1305,
		hkdf_sha256_extract                  = primitives.hkdf_sha256_extract,
		hkdf_sha256_expand                   = primitives.hkdf_sha256_expand,
		header_protection_mask_with_aes_128  = primitives.header_protection_mask_with_aes_128,
		header_protection_mask_with_chacha20 = primitives.header_protection_mask_with_chacha20,
		sha256                               = primitives.sha256,
		hmac_sha256                          = primitives.hmac_sha256,
		x25519                               = primitives.x25519,
		ed25519_public_key                   = primitives.ed25519_public_key,
		ed25519_sign                         = primitives.ed25519_sign,
		ed25519_verify                       = primitives.ed25519_verify,
	}
}
