// The client of the protocol of `remote_display` (src/md/features/session.md): the stream of one connection, seen from
// the viewer. It reads the bytes of the machine one record at a time, checks each record at the border of the contract,
// rebuilds the screen from the screen pieces, and holds the bytes that the viewer writes. It has no socket, no thread
// and no window: the connection thread drives it, and the host tests drive it byte by byte.
package session

import "base:intrinsics"
import protocol "modus:contract/remote_display"

// Where the session is. Each record of the machine moves it by one rule; a refusal is the last phase.
Phase :: enum u8 {
	Before_Screen_Size, // No Screen_Size yet: no frame, no screen piece, no pointer.
	Between_Frames,     // A screen exists, and no viewer frame is in progress.
	In_Frame,           // A Viewer_Frame_Start came, and its Viewer_Frame_End did not.
	Refused,            // The session refused a record: it takes no more bytes.
}

// Why the session refused a record of the machine. The connection then closes with the code Bad_Record.
Refusal :: enum u8 {
	None,
	Record,                      // The border of the contract refused it: Session.record_problem says why.
	Screen_Piece_Code,           // The decoder refused the code of a screen piece: Session.screen_piece_problem says why.
	Frame_Before_Screen_Size,    // A Viewer_Frame_Start before the first Screen_Size.
	Screen_Size_In_Frame,        // A Screen_Size in a viewer frame: a frame shows one moment of one screen.
	Frame_Start_In_Frame,        // A Viewer_Frame_Start in a viewer frame.
	Serial_Out_Of_Order,         // A Viewer_Frame_Start whose serial is not the last one plus one.
	Piece_Outside_Frame,         // A screen piece with no viewer frame in progress.
	Piece_Past_Count,            // A screen piece past the count of its Viewer_Frame_Start.
	Piece_Past_Bytes,            // A screen piece past the bytes of its Viewer_Frame_Start.
	Frame_End_Outside_Frame,     // A Viewer_Frame_End with no viewer frame in progress.
	Frame_End_Other_Serial,      // A Viewer_Frame_End that names another viewer frame.
	Frame_End_Before_Last_Piece, // A Viewer_Frame_End before the last screen piece of its count.
}

@(rodata)
REFUSAL_SENTENCES := [Refusal]string {
	.None                        = "the session holds",
	.Record                      = "the record broke a rule of the contract",
	.Screen_Piece_Code           = "the code of a screen piece is damaged",
	.Frame_Before_Screen_Size    = "a viewer frame came before the size of the screen",
	.Screen_Size_In_Frame        = "a size of the screen came in a viewer frame",
	.Frame_Start_In_Frame        = "a viewer frame started in another one",
	.Serial_Out_Of_Order         = "a viewer frame did not have the next serial",
	.Piece_Outside_Frame         = "a screen piece came outside a viewer frame",
	.Piece_Past_Count            = "a screen piece came past the count of its viewer frame",
	.Piece_Past_Bytes            = "a screen piece came past the bytes of its viewer frame",
	.Frame_End_Outside_Frame     = "the end of a viewer frame came outside a viewer frame",
	.Frame_End_Other_Serial      = "the end of a viewer frame named another viewer frame",
	.Frame_End_Before_Last_Piece = "a viewer frame ended before its last screen piece",
}

// What one call of session_received gives.
Outcome :: enum u8 {
	Need_More,     // The record is not whole yet.
	Taken,         // A whole record, which changes nothing that the window shows yet.
	Screen_Size,   // A new size of the screen: the next viewer frame covers it whole.
	Pointer_Moved, // A Pointer_Place between viewer frames: Session.pointer.
	Frame_Whole,   // A Viewer_Frame_End: the damage of the frame is in Session.damage, until the next bytes.
	Refused,       // The session refused a record: Session.refusal.
}

// What a key or a pointer of the user became.
Input_Result :: enum u8 {
	Queued,    // In the bytes that the viewer writes.
	Input_Off, // The user did not turn the input on.
	Refused,   // The border of the viewer direction refuses it, or the session ended.
	Full,      // The bytes that the viewer writes have no room; the record does not go.
}

// The rectangles of a viewer frame that the window uploads. Past it, they join into their bounding rectangle.
DAMAGE_CAPACITY :: 16
// The bytes that the viewer writes and that QUIC did not take yet.
OUTGOING_CAPACITY :: 4096
// The room that a Viewer_Frame_Taken needs: a key or a pointer never takes it.
TAKEN_RECORD_SIZE :: protocol.RECORD_HEADER_SIZE + size_of(protocol.Viewer_Frame_Taken_Body)
// The largest record of the viewer direction.
VIEWER_RECORD_LIMIT :: protocol.RECORD_HEADER_SIZE + protocol.VIEWER_BODY_LIMIT

Rectangle :: struct {
	x, y, width, height: u32,
}

Session :: struct {
	phase:                Phase,
	refusal:              Refusal,
	record_problem:       protocol.Record_Problem,
	screen_piece_problem: protocol.Screen_Piece_Problem,
	// The record that is being read: its header, then its body, in one buffer of the largest record.
	incoming:             []u8,
	incoming_count:       int,
	header:               protocol.Record_Header,
	// A screen piece decodes here first: a damaged piece changes no pixel of the screen.
	piece_pixels:         []u32,
	// The screen that the session rebuilds: 0x00RRGGBB, rows of screen.width pixels.
	screen:               protocol.Screen,
	pixels:               []u32,
	pointer:              protocol.Pointer_Place_Body,
	// The viewer frame in progress, or the last whole one.
	frame_serial:         u64,
	pieces_left:          u32,
	bytes_left:           u64,
	damage:               [DAMAGE_CAPACITY]Rectangle,
	damage_count:         int,
	damage_joins:         u64, // Viewer frames whose damage passed the capacity and joined into one rectangle.
	frames_whole:         u64,
	// The bytes that the viewer writes: outgoing[outgoing_start:outgoing_end] waits for QUIC.
	input_allowed:        bool,
	outgoing:             []u8,
	outgoing_start:       int,
	outgoing_end:         int,
	// A pointer record at the end of the waiting bytes, which a next move with the same buttons replaces.
	pointer_waiting:      bool,
	pointer_waiting_at:   int,
}

// session_init makes the buffers of a session, and queues its Session_Start: the first record of the viewer.
session_init :: proc(s: ^Session, input_allowed: bool, allocator := context.allocator) {
	s^ = {input_allowed = input_allowed}
	s.incoming = make([]u8, protocol.RECORD_HEADER_SIZE + protocol.SERVICE_BODY_LIMIT, allocator)
	s.piece_pixels = make([]u32, protocol.SCREEN_PIECE_PIXEL_LIMIT, allocator)
	s.pixels = make([]u32, protocol.SCREEN_WIDTH_LIMIT * protocol.SCREEN_HEIGHT_LIMIT, allocator)
	s.outgoing = make([]u8, OUTGOING_CAPACITY, allocator)
	queued := outgoing_queue(s, .Session_Start, protocol.Session_Start_Body{version = protocol.PROTOCOL_VERSION}, 0)
	assert(queued, "an empty buffer holds Session_Start")
}

session_destroy :: proc(s: ^Session, allocator := context.allocator) {
	delete(s.incoming, allocator)
	delete(s.piece_pixels, allocator)
	delete(s.pixels, allocator)
	delete(s.outgoing, allocator)
	s^ = {}
}

////////////////////////////////
// The read

// session_receive_space gives the bytes that the session wants next: the rest of the header, then the rest of the body.
// The caller reads at most that many bytes into it, so a header past its bound is refused before any byte of its body
// is read. nil: the session refused a record and takes nothing more.
session_receive_space :: proc(s: ^Session) -> []u8 {
	if s.phase == .Refused {
		return nil
	}
	if s.incoming_count < protocol.RECORD_HEADER_SIZE {
		return s.incoming[s.incoming_count:protocol.RECORD_HEADER_SIZE]
	}
	return s.incoming[s.incoming_count:protocol.RECORD_HEADER_SIZE + int(s.header.length)]
}

// session_received counts the bytes that the caller wrote into session_receive_space, and acts when the record is
// whole. count is at most the length of that space.
session_received :: proc(s: ^Session, count: int) -> Outcome {
	if s.phase == .Refused {
		return .Refused
	}
	assert(count >= 0 && count <= len(session_receive_space(s)), "the bytes of the stream past the space of the session")
	header_was_whole := s.incoming_count >= protocol.RECORD_HEADER_SIZE
	s.incoming_count += count
	if !header_was_whole {
		if s.incoming_count < protocol.RECORD_HEADER_SIZE {
			return .Need_More
		}
		s.header, _ = protocol.header_read(s.incoming[:protocol.RECORD_HEADER_SIZE])
		if problem := protocol.record_length_problem(s.header, .To_Viewer); problem != .None {
			return refuse_record(s, problem)
		}
	}
	total := protocol.RECORD_HEADER_SIZE + int(s.header.length)
	if s.incoming_count < total {
		return .Need_More
	}
	s.incoming_count = 0
	record, problem := protocol.service_record_check(s.header, s.incoming[protocol.RECORD_HEADER_SIZE:total], s.screen)
	if problem != .None {
		return refuse_record(s, problem)
	}
	return record_take(s, record, total)
}

// session_receive gives bytes that the caller holds already, up to the end of the next record. It gives the bytes that
// it took: the caller calls it again with the rest after a whole record.
session_receive :: proc(s: ^Session, bytes: []u8) -> (taken: int, outcome: Outcome) {
	space := session_receive_space(s)
	if space == nil {
		return 0, .Refused
	}
	taken = copy(space, bytes)
	return taken, session_received(s, taken)
}

@(private = "file")
refuse_record :: proc(s: ^Session, problem: protocol.Record_Problem) -> Outcome {
	s.record_problem = problem
	return refuse(s, .Record)
}

@(private = "file")
refuse :: proc(s: ^Session, refusal: Refusal) -> Outcome {
	s.phase = .Refused
	s.refusal = refusal
	return .Refused
}

// record_take acts on one record that the border took.
@(private = "file")
record_take :: proc(s: ^Session, record: protocol.Service_Record, length: int) -> Outcome {
	switch record.kind {
	case .None, .Viewer_Frame_Taken, .Screen_Piece_Request, .Key, .Pointer, .Session_Start:
		// The border takes a kind of this direction only.
		return refuse_record(s, .Wrong_Direction)
	case .Screen_Size:
		if s.phase == .In_Frame {
			return refuse(s, .Screen_Size_In_Frame)
		}
		s.screen = {record.screen_size.width, record.screen_size.height}
		// The pixels of another size mean nothing in the new rows: black until the whole frame that follows.
		intrinsics.mem_zero(raw_data(s.pixels), int(s.screen.width) * int(s.screen.height) * size_of(u32))
		s.phase = .Between_Frames
		return .Screen_Size
	case .Pointer_Place:
		// The border refuses a place before Screen_Size: no place is inside a screen of zero pixels.
		s.pointer = record.pointer_place
		return s.phase == .In_Frame ? .Taken : .Pointer_Moved
	case .Viewer_Frame_Start:
		start := record.viewer_frame_start
		switch s.phase {
		case .Before_Screen_Size:
			return refuse(s, .Frame_Before_Screen_Size)
		case .In_Frame:
			return refuse(s, .Frame_Start_In_Frame)
		case .Refused:
			return .Refused
		case .Between_Frames:
		}
		if start.serial != s.frame_serial + 1 {
			return refuse(s, .Serial_Out_Of_Order)
		}
		s.phase = .In_Frame
		s.frame_serial = start.serial
		s.pieces_left = start.screen_piece_count
		s.bytes_left = start.bytes
		s.damage_count = 0
		return .Taken
	case .Screen_Piece:
		return screen_piece_take(s, record, length)
	case .Viewer_Frame_End:
		if s.phase != .In_Frame {
			return refuse(s, .Frame_End_Outside_Frame)
		}
		if record.viewer_frame_end.serial != s.frame_serial {
			return refuse(s, .Frame_End_Other_Serial)
		}
		if s.pieces_left != 0 {
			return refuse(s, .Frame_End_Before_Last_Piece)
		}
		s.phase = .Between_Frames
		s.frames_whole += 1
		// The take goes at once: the service codes the next frame while the window uploads this one.
		queued := outgoing_queue(s, .Viewer_Frame_Taken, protocol.Viewer_Frame_Taken_Body{serial = s.frame_serial}, 0)
		assert(queued, "a key or a pointer took the room of Viewer_Frame_Taken")
		s.pointer_waiting = false
		return .Frame_Whole
	}
	return refuse_record(s, .Unknown_Kind)
}

@(private = "file")
screen_piece_take :: proc(s: ^Session, record: protocol.Service_Record, length: int) -> Outcome {
	piece := record.screen_piece
	if s.phase != .In_Frame {
		return refuse(s, .Piece_Outside_Frame)
	}
	if s.pieces_left == 0 {
		return refuse(s, .Piece_Past_Count)
	}
	if u64(length) > s.bytes_left {
		return refuse(s, .Piece_Past_Bytes)
	}
	count := int(piece.width) * int(piece.height)
	if problem := protocol.screen_piece_decode(record.coded, s.piece_pixels[:count]); problem != .None {
		s.screen_piece_problem = problem
		return refuse(s, .Screen_Piece_Code)
	}
	stride, width := int(s.screen.width), int(piece.width)
	for row in 0 ..< int(piece.height) {
		copy(s.pixels[(int(piece.y) + row) * stride + int(piece.x):][:width], s.piece_pixels[row * width:][:width])
	}
	damage_add(s, {piece.x, piece.y, piece.width, piece.height})
	s.pieces_left -= 1
	s.bytes_left -= u64(length)
	return .Taken
}

////////////////////////////////
// The damage of a viewer frame

// damage_add adds the rectangle of a screen piece. The service sends the pieces of a rectangle row after row, so a piece
// that continues a rectangle on its row or under it joins it, and a whole rectangle of the damage stays one rectangle.
@(private = "file")
damage_add :: proc(s: ^Session, added: Rectangle) {
	for index in 0 ..< s.damage_count {
		if rectangle_extend(&s.damage[index], added) {
			damage_join_from(s, index)
			return
		}
	}
	if s.damage_count < DAMAGE_CAPACITY {
		s.damage[s.damage_count] = added
		s.damage_count += 1
		return
	}
	bounds := added
	for rectangle in s.damage[:s.damage_count] {
		bounds = rectangle_union(bounds, rectangle)
	}
	s.damage[0] = bounds
	s.damage_count = 1
	s.damage_joins += 1
}

// damage_join_from joins a rectangle that grew with another one that it now continues: a row of pieces that became as
// wide as the row above it.
@(private = "file")
damage_join_from :: proc(s: ^Session, grown: int) {
	for index in 0 ..< s.damage_count {
		if index != grown && rectangle_extend(&s.damage[index], s.damage[grown]) {
			s.damage_count -= 1
			s.damage[grown] = s.damage[s.damage_count]
			return
		}
	}
}

// rectangle_extend makes into one rectangle a rectangle and another that continues it on its row or under it.
rectangle_extend :: proc(into: ^Rectangle, added: Rectangle) -> bool {
	if into.y == added.y && into.height == added.height && into.x + into.width == added.x {
		into.width += added.width
		return true
	}
	if into.x == added.x && into.width == added.width && into.y + into.height == added.y {
		into.height += added.height
		return true
	}
	return false
}

rectangle_union :: proc(first, second: Rectangle) -> Rectangle {
	left, top := min(first.x, second.x), min(first.y, second.y)
	right, bottom := max(first.x + first.width, second.x + second.width), max(first.y + first.height, second.y + second.height)
	return {left, top, right - left, bottom - top}
}

////////////////////////////////
// The write

// session_outgoing gives the bytes that wait for QUIC, in order.
session_outgoing :: proc(s: ^Session) -> []u8 {
	return s.outgoing[s.outgoing_start:s.outgoing_end]
}

// session_written counts the bytes of session_outgoing that QUIC took.
session_written :: proc(s: ^Session, count: int) {
	assert(count >= 0 && count <= s.outgoing_end - s.outgoing_start, "QUIC took more bytes than wait")
	s.outgoing_start += count
	// A pointer record that QUIC began to take cannot change any more.
	if s.pointer_waiting && s.pointer_waiting_at < s.outgoing_start {
		s.pointer_waiting = false
	}
	if s.outgoing_start == s.outgoing_end {
		s.outgoing_start, s.outgoing_end = 0, 0
	}
}

// session_key queues a key of the user.
session_key :: proc(s: ^Session, key: protocol.Key_Body) -> Input_Result {
	if result := input_check(s, .Key, key); result != .Queued {
		return result
	}
	if !outgoing_queue(s, .Key, key, TAKEN_RECORD_SIZE) {
		return .Full
	}
	// A key after a pointer keeps their order: the pointer record before it no longer changes.
	s.pointer_waiting = false
	return .Queued
}

// session_pointer queues the pointer of the user, at a place of the screen of the machine. A move with the same buttons
// and no wheel replaces a pointer record that still waits at the end of the bytes.
session_pointer :: proc(s: ^Session, pointer: protocol.Pointer_Body) -> Input_Result {
	if result := input_check(s, .Pointer, pointer); result != .Queued {
		return result
	}
	if s.pointer_waiting && pointer.wheel == 0 {
		body := s.outgoing[s.pointer_waiting_at + protocol.RECORD_HEADER_SIZE:][:size_of(protocol.Pointer_Body)]
		waiting: protocol.Pointer_Body
		intrinsics.mem_copy_non_overlapping(&waiting, raw_data(body), size_of(protocol.Pointer_Body))
		if waiting.buttons == pointer.buttons && waiting.wheel == 0 {
			value := pointer
			intrinsics.mem_copy_non_overlapping(raw_data(body), &value, size_of(protocol.Pointer_Body))
			return .Queued
		}
	}
	if !outgoing_queue(s, .Pointer, pointer, TAKEN_RECORD_SIZE) {
		return .Full
	}
	// The queue can move the waiting bytes to the start of the buffer: the record starts where its bytes end less its size.
	s.pointer_waiting = true
	s.pointer_waiting_at = s.outgoing_end - (protocol.RECORD_HEADER_SIZE + size_of(protocol.Pointer_Body))
	return .Queued
}

// input_check gives Queued when a key or a pointer can go: the input is on, the session runs, and the border of the
// service would take the record.
@(private = "file")
input_check :: proc(s: ^Session, kind: protocol.Record_Kind, body: $T) -> Input_Result {
	if !s.input_allowed {
		return .Input_Off
	}
	if s.phase == .Refused {
		return .Refused
	}
	bytes: [VIEWER_RECORD_LIMIT]u8
	written, ok := protocol.record_write(bytes[:], kind, body)
	if !ok {
		return .Refused
	}
	header, _ := protocol.header_read(written)
	if _, problem := protocol.viewer_record_check(header, written[protocol.RECORD_HEADER_SIZE:], s.screen); problem != .None {
		return .Refused
	}
	return .Queued
}

// outgoing_queue writes a record at the end of the waiting bytes, and keeps `reserve` bytes free after it.
@(private = "file")
outgoing_queue :: proc(s: ^Session, kind: protocol.Record_Kind, body: $T, reserve: int) -> bool {
	size := protocol.RECORD_HEADER_SIZE + size_of(T)
	if len(s.outgoing) - s.outgoing_end < size + reserve && s.outgoing_start > 0 {
		// The bytes that QUIC took leave room at the start: the waiting bytes move there.
		waiting := copy(s.outgoing, s.outgoing[s.outgoing_start:s.outgoing_end])
		if s.pointer_waiting {
			s.pointer_waiting_at -= s.outgoing_start
		}
		s.outgoing_start, s.outgoing_end = 0, waiting
	}
	if len(s.outgoing) - s.outgoing_end < size + reserve {
		return false
	}
	written, ok := protocol.record_write(s.outgoing[s.outgoing_end:], kind, body)
	if !ok {
		return false
	}
	s.outgoing_end += len(written)
	return true
}
