package session

import "base:intrinsics"
import "core:strings"
import "core:testing"
import protocol "modus:contract/remote_display"

// The tests give the session what the machine must not send first, and check the refusal: its phase, its reason, and
// that the screen did not change. The edges come first: 0, 1, the bound, one past it. A whole session is the last case.

@(private = "file")
HEADER :: protocol.RECORD_HEADER_SIZE

@(private = "file")
record_bytes :: proc(kind: protocol.Record_Kind, body: $T) -> []u8 {
	out := make([]u8, HEADER + size_of(T), context.temp_allocator)
	bytes, _ := protocol.record_write(out, kind, body)
	return bytes
}

// header_bytes gives a header alone, with any kind word and any length: a word that names no kind must stay a word.
@(private = "file")
header_bytes :: proc(kind_word: u32, length: u32) -> []u8 {
	out := make([]u8, HEADER, context.temp_allocator)
	intrinsics.unaligned_store((^u32)(&out[0]), kind_word)
	intrinsics.unaligned_store((^u32)(&out[4]), length)
	return out
}

// piece_bytes gives a Screen_Piece record of one color.
@(private = "file")
piece_bytes :: proc(x, y, width, height: u32, color: u32) -> []u8 {
	pixels := make([]u32, int(width) * int(height), context.temp_allocator)
	for &pixel in pixels {
		pixel = color
	}
	out := make([]u8, HEADER + size_of(protocol.Screen_Piece_Header) + int(width * height) * protocol.CODED_PIXEL_LIMIT, context.temp_allocator)
	bytes, ok := protocol.screen_piece_record_write(out, pixels, int(width), 0, 0, width, height)
	assert(ok)
	// The record names the place on the screen; the pixels came from a picture of the piece alone.
	intrinsics.unaligned_store((^u32)(&bytes[HEADER]), x)
	intrinsics.unaligned_store((^u32)(&bytes[HEADER + 4]), y)
	return bytes
}

// feed gives bytes to the session in chunks of `chunk` bytes, and gives the last outcome that is not Need_More.
@(private = "file")
feed :: proc(s: ^Session, bytes: []u8, chunk := max(int)) -> Outcome {
	last := Outcome.Need_More
	rest := bytes
	for len(rest) > 0 {
		taken, outcome := session_receive(s, rest[:min(len(rest), chunk)])
		if outcome == .Refused {
			return .Refused
		}
		if outcome != .Need_More {
			last = outcome
		}
		rest = rest[taken:]
	}
	return last
}

@(private = "file")
frame_start_bytes :: proc(serial: u64, count: u32, bytes: u64) -> []u8 {
	return record_bytes(.Viewer_Frame_Start, protocol.Viewer_Frame_Start_Body{serial = serial, screen_piece_count = count, bytes = bytes})
}

// A session with a screen of width x height, between frames.
@(private = "file")
session_with_screen :: proc(t: ^testing.T, s: ^Session, width, height: u32, input := false) {
	session_init(s, input)
	testing.expect_value(t, feed(s, record_bytes(.Screen_Size, protocol.Screen_Size_Body{width, height})), Outcome.Screen_Size)
}

@(private = "file")
expect_refused :: proc(t: ^testing.T, s: ^Session, refusal: Refusal, problem := protocol.Record_Problem.None, loc := #caller_location) {
	testing.expect_value(t, s.phase, Phase.Refused, loc = loc)
	testing.expect_value(t, s.refusal, refusal, loc = loc)
	testing.expect_value(t, s.record_problem, problem, loc = loc)
	testing.expect(t, session_receive_space(s) == nil, "a refused session takes no more bytes", loc = loc)
	testing.expect_value(t, session_received(s, 0), Outcome.Refused, loc = loc)
}

// A header is refused on its kind and its length alone: the session asks for no byte of its body.
@(test)
a_header_is_refused_before_its_body :: proc(t: ^testing.T) {
	s: Session
	// A Screen_Piece one byte past the bound of the direction.
	session_init(&s, false)
	testing.expect_value(t, feed(&s, header_bytes(u32(protocol.Record_Kind.Screen_Piece), protocol.SERVICE_BODY_LIMIT + 1)), Outcome.Refused)
	expect_refused(t, &s, .Record, .Past_Bound)
	session_destroy(&s)
	// The largest length word.
	session_init(&s, false)
	testing.expect_value(t, feed(&s, header_bytes(u32(protocol.Record_Kind.Screen_Size), max(u32))), Outcome.Refused)
	expect_refused(t, &s, .Record, .Past_Bound)
	session_destroy(&s)
	// The words that name no kind: 0, the word between the two directions, the largest word.
	for word in ([]u32{0, u32(protocol.Record_Kind.Pointer_Place) + 1, u32(protocol.Record_Kind.Viewer_Frame_Taken) - 1, max(u32)}) {
		session_init(&s, false)
		testing.expect_value(t, feed(&s, header_bytes(word, 8)), Outcome.Refused)
		expect_refused(t, &s, .Record, .Unknown_Kind)
		session_destroy(&s)
	}
	// Each kind of the viewer direction.
	for kind in ([]protocol.Record_Kind{.Viewer_Frame_Taken, .Screen_Piece_Request, .Key, .Pointer, .Session_Start}) {
		session_init(&s, false)
		testing.expect_value(t, feed(&s, header_bytes(u32(kind), protocol.BODY_SIZES[kind])), Outcome.Refused)
		expect_refused(t, &s, .Record, .Wrong_Direction)
		session_destroy(&s)
	}
	// A length one short and one past the length of its kind.
	for length in ([]u32{0, size_of(protocol.Screen_Size_Body) - 1, size_of(protocol.Screen_Size_Body) + 1}) {
		session_init(&s, false)
		testing.expect_value(t, feed(&s, header_bytes(u32(protocol.Record_Kind.Screen_Size), length)), Outcome.Refused)
		expect_refused(t, &s, .Record, .Wrong_Length)
		session_destroy(&s)
	}
	// A screen piece shorter than its own header.
	session_init(&s, false)
	testing.expect_value(t, feed(&s, header_bytes(u32(protocol.Record_Kind.Screen_Piece), size_of(protocol.Screen_Piece_Header) - 1)), Outcome.Refused)
	expect_refused(t, &s, .Record, .Wrong_Length)
	session_destroy(&s)
}

// The space of the session is the header, then exactly the body: the read never takes a byte of the next record.
@(test)
the_space_ends_at_the_end_of_the_record :: proc(t: ^testing.T) {
	s: Session
	session_init(&s, false)
	defer session_destroy(&s)
	testing.expect_value(t, len(session_receive_space(&s)), HEADER)
	bytes := record_bytes(.Screen_Size, protocol.Screen_Size_Body{4, 2})
	testing.expect_value(t, session_received(&s, copy(session_receive_space(&s), bytes[:HEADER - 1])), Outcome.Need_More)
	testing.expect_value(t, len(session_receive_space(&s)), 1)
	testing.expect_value(t, session_received(&s, copy(session_receive_space(&s), bytes[HEADER - 1:])), Outcome.Need_More)
	testing.expect_value(t, len(session_receive_space(&s)), size_of(protocol.Screen_Size_Body))
	// Two records in one slice: the first call takes the first record only.
	// A slice has no capacity of its own: append_bytes makes each longer slice.
	both: []u8
	two := [2][]u8{bytes[HEADER:], record_bytes(.Screen_Size, protocol.Screen_Size_Body{8, 8})}
	for part in two {
		both = append_bytes(both, part)
	}
	taken, outcome := session_receive(&s, both)
	testing.expect_value(t, taken, size_of(protocol.Screen_Size_Body))
	testing.expect_value(t, outcome, Outcome.Screen_Size)
	testing.expect_value(t, s.screen, protocol.Screen{4, 2})
}

@(private = "file")
append_bytes :: proc(into: []u8, bytes: []u8) -> []u8 {
	out := make([]u8, len(into) + len(bytes), context.temp_allocator)
	copy(out, into)
	copy(out[len(into):], bytes)
	return out
}

// A screen of 0 pixels, and one pixel past the limit on each side, are refused; the limit itself is taken.
@(test)
a_screen_size_past_its_limit_is_refused :: proc(t: ^testing.T) {
	s: Session
	cases := [?]protocol.Screen_Size_Body{{0, 1}, {1, 0}, {protocol.SCREEN_WIDTH_LIMIT + 1, 1}, {1, protocol.SCREEN_HEIGHT_LIMIT + 1}, {max(u32), max(u32)}}
	for size in cases {
		session_init(&s, false)
		testing.expect_value(t, feed(&s, record_bytes(.Screen_Size, size)), Outcome.Refused)
		expect_refused(t, &s, .Record, .Outside_Screen)
		session_destroy(&s)
	}
	session_with_screen(t, &s, protocol.SCREEN_WIDTH_LIMIT, protocol.SCREEN_HEIGHT_LIMIT)
	testing.expect_value(t, s.screen, protocol.Screen{protocol.SCREEN_WIDTH_LIMIT, protocol.SCREEN_HEIGHT_LIMIT})
	session_destroy(&s)
}

// The order of the viewer frames: each rule refused by its own reason.
@(test)
the_order_of_the_frames_is_checked :: proc(t: ^testing.T) {
	s: Session
	// A frame before the size of the screen.
	session_init(&s, false)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 0, 0)), Outcome.Refused)
	expect_refused(t, &s, .Frame_Before_Screen_Size)
	session_destroy(&s)
	// A pointer before the size of the screen: no place is inside a screen of zero pixels.
	session_init(&s, false)
	testing.expect_value(t, feed(&s, record_bytes(.Pointer_Place, protocol.Pointer_Place_Body{})), Outcome.Refused)
	expect_refused(t, &s, .Record, .Outside_Screen)
	session_destroy(&s)
	// The serial 0, and a serial that skips one.
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, frame_start_bytes(0, 0, 0)), Outcome.Refused)
	expect_refused(t, &s, .Record, .Bad_Field)
	session_destroy(&s)
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, frame_start_bytes(2, 0, 0)), Outcome.Refused)
	expect_refused(t, &s, .Serial_Out_Of_Order)
	session_destroy(&s)
	// A frame in a frame, and a size of the screen in a frame.
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 1, 64)), Outcome.Taken)
	testing.expect_value(t, feed(&s, frame_start_bytes(2, 0, 0)), Outcome.Refused)
	expect_refused(t, &s, .Frame_Start_In_Frame)
	session_destroy(&s)
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 1, 64)), Outcome.Taken)
	testing.expect_value(t, feed(&s, record_bytes(.Screen_Size, protocol.Screen_Size_Body{8, 8})), Outcome.Refused)
	expect_refused(t, &s, .Screen_Size_In_Frame)
	session_destroy(&s)
	// The end of a frame outside a frame, of another frame, and before its last piece.
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, record_bytes(.Viewer_Frame_End, protocol.Viewer_Frame_End_Body{serial = 1})), Outcome.Refused)
	expect_refused(t, &s, .Frame_End_Outside_Frame)
	session_destroy(&s)
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 0, 0)), Outcome.Taken)
	testing.expect_value(t, feed(&s, record_bytes(.Viewer_Frame_End, protocol.Viewer_Frame_End_Body{serial = 2})), Outcome.Refused)
	expect_refused(t, &s, .Frame_End_Other_Serial)
	session_destroy(&s)
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 1, 64)), Outcome.Taken)
	testing.expect_value(t, feed(&s, record_bytes(.Viewer_Frame_End, protocol.Viewer_Frame_End_Body{serial = 1})), Outcome.Refused)
	expect_refused(t, &s, .Frame_End_Before_Last_Piece)
	session_destroy(&s)
}

// A screen piece outside its frame, past its count, past its bytes, outside the screen, too large, or with a damaged
// code is refused, and no pixel of the screen changes.
@(test)
a_screen_piece_past_its_frame_is_refused :: proc(t: ^testing.T) {
	RED :: 0x00FF_0000
	s: Session
	// Outside a frame.
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, piece_bytes(0, 0, 1, 1, RED)), Outcome.Refused)
	expect_refused(t, &s, .Piece_Outside_Frame)
	testing.expect_value(t, s.pixels[0], 0)
	session_destroy(&s)
	// A count of 0, then one piece.
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 0, 0)), Outcome.Taken)
	testing.expect_value(t, feed(&s, piece_bytes(0, 0, 1, 1, RED)), Outcome.Refused)
	expect_refused(t, &s, .Piece_Past_Count)
	session_destroy(&s)
	// The least bytes of one piece: its two headers. A piece of one pixel has one byte more.
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 1, HEADER + size_of(protocol.Screen_Piece_Header))), Outcome.Taken)
	testing.expect_value(t, feed(&s, piece_bytes(0, 0, 1, 1, RED)), Outcome.Refused)
	expect_refused(t, &s, .Piece_Past_Bytes)
	testing.expect_value(t, s.pixels[0], 0)
	session_destroy(&s)
	// One pixel past the right edge and past the bottom edge.
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 1, 1024)), Outcome.Taken)
	testing.expect_value(t, feed(&s, piece_bytes(7, 0, 2, 1, RED)), Outcome.Refused)
	expect_refused(t, &s, .Record, .Outside_Screen)
	session_destroy(&s)
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 1, 1024)), Outcome.Taken)
	testing.expect_value(t, feed(&s, piece_bytes(0, 7, 1, 2, RED)), Outcome.Refused)
	expect_refused(t, &s, .Record, .Outside_Screen)
	session_destroy(&s)
	// One column past the largest piece.
	session_with_screen(t, &s, 256, 64)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 1, protocol.VIEWER_FRAME_BYTES_LIMIT)), Outcome.Taken)
	wide := make([]u8, HEADER + size_of(protocol.Screen_Piece_Header) + 4, context.temp_allocator)
	copy(wide, record_bytes(.Screen_Piece, protocol.Screen_Piece_Header{width = protocol.SCREEN_PIECE_WIDTH + 1, height = 1, coded_length = 4}))
	intrinsics.unaligned_store((^u32)(&wide[4]), u32(size_of(protocol.Screen_Piece_Header) + 4))
	testing.expect_value(t, feed(&s, wide), Outcome.Refused)
	expect_refused(t, &s, .Record, .Empty_Rectangle)
	session_destroy(&s)
	// The reserved tag of a color with alpha in place of the first code: the screen keeps its pixels.
	session_with_screen(t, &s, 8, 8)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 1, 1024)), Outcome.Taken)
	damaged := piece_bytes(0, 0, 2, 2, RED)
	damaged[HEADER + size_of(protocol.Screen_Piece_Header)] = protocol.TAG_RESERVED
	testing.expect_value(t, feed(&s, damaged), Outcome.Refused)
	expect_refused(t, &s, .Screen_Piece_Code)
	testing.expect_value(t, s.screen_piece_problem, protocol.Screen_Piece_Problem.Reserved_Tag)
	testing.expect_value(t, s.pixels[0], 0)
	session_destroy(&s)
}

// The damage of a frame: the pieces of one rectangle join into it, and past the capacity all join into their bounds.
@(test)
the_damage_joins_the_pieces_of_a_rectangle :: proc(t: ^testing.T) {
	s: Session
	// Four pieces of 128 x 64, row after row: one rectangle.
	session_with_screen(t, &s, 256, 128)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 4, protocol.VIEWER_FRAME_BYTES_LIMIT)), Outcome.Taken)
	for index in u32(0) ..< 4 {
		testing.expect_value(t, feed(&s, piece_bytes((index % 2) * 128, (index / 2) * 64, 128, 64, 0x0012_3456)), Outcome.Taken)
	}
	testing.expect_value(t, feed(&s, record_bytes(.Viewer_Frame_End, protocol.Viewer_Frame_End_Body{serial = 1})), Outcome.Frame_Whole)
	testing.expect_value(t, s.damage_count, 1)
	testing.expect_value(t, s.damage[0], Rectangle{0, 0, 256, 128})
	session_destroy(&s)
	// The capacity of rectangles that do not touch, then one more: one bounding rectangle.
	session_with_screen(t, &s, 64, 64)
	count := u32(DAMAGE_CAPACITY + 1)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, count, protocol.VIEWER_FRAME_BYTES_LIMIT)), Outcome.Taken)
	for index in u32(0) ..< count {
		testing.expect_value(t, feed(&s, piece_bytes((index % 8) * 8, (index / 8) * 8 * 2, 1, 1, 0x0000_00FF)), Outcome.Taken)
		if index == count - 2 {
			testing.expect_value(t, s.damage_count, DAMAGE_CAPACITY)
		}
	}
	testing.expect_value(t, s.damage_count, 1)
	testing.expect_value(t, s.damage_joins, 1)
	testing.expect_value(t, s.damage[0], Rectangle{0, 0, 57, 33})
	session_destroy(&s)
}

// The input: each key and pointer that the border of the service refuses stays in the viewer.
@(test)
the_input_is_refused_at_the_border_of_the_viewer :: proc(t: ^testing.T) {
	s: Session
	start_bytes := len(record_bytes(.Session_Start, protocol.Session_Start_Body{version = protocol.PROTOCOL_VERSION}))
	// The input off.
	session_with_screen(t, &s, 8, 8, input = false)
	testing.expect_value(t, session_key(&s, {code = 0x1E, pressed = 1}), Input_Result.Input_Off)
	testing.expect_value(t, session_pointer(&s, {x = 1, y = 1}), Input_Result.Input_Off)
	testing.expect_value(t, len(session_outgoing(&s)), start_bytes)
	session_destroy(&s)
	// A pointer before the size of the screen.
	session_init(&s, true)
	testing.expect_value(t, session_pointer(&s, {x = 0, y = 0}), Input_Result.Refused)
	session_destroy(&s)
	session_with_screen(t, &s, 8, 8, input = true)
	defer session_destroy(&s)
	refused_keys := [?]protocol.Key_Body{
		{code = 0, pressed = 1},                                     // no key
		{code = protocol.KEY_CODE_LIMIT + 1, pressed = 1},           // past the largest code
		{code = 0x1E | protocol.KEY_RELEASE_BIT, pressed = 1},       // the release bit in the code
		{code = 0x1E, pressed = 2},                                  // pressed is 0 or 1
		{code = 0x1E, character = protocol.CHARACTER_LIMIT + 1},     // past the largest code point
		{code = 0x1E, character = 0xD800},                           // a surrogate
		{code = 0x1E, modifiers = protocol.KEY_MODIFIERS + 1},       // an unknown modifier bit
	}
	for key in refused_keys {
		testing.expect_value(t, session_key(&s, key), Input_Result.Refused)
	}
	refused_pointers := [?]protocol.Pointer_Body{
		{x = 8, y = 0},                                     // one past the width
		{x = 0, y = 8},                                     // one past the height
		{x = max(u32), y = 0},
		{x = 0, y = 0, buttons = protocol.POINTER_BUTTONS + 1},
		{x = 0, y = 0, wheel = protocol.WHEEL_NOTCHES_LIMIT + 1},
		{x = 0, y = 0, wheel = -protocol.WHEEL_NOTCHES_LIMIT - 1},
	}
	for pointer in refused_pointers {
		testing.expect_value(t, session_pointer(&s, pointer), Input_Result.Refused)
	}
	testing.expect_value(t, len(session_outgoing(&s)), start_bytes)
	// The edges that go: the last pixel, the largest code, the largest wheel.
	testing.expect_value(t, session_pointer(&s, {x = 7, y = 7, wheel = protocol.WHEEL_NOTCHES_LIMIT}), Input_Result.Queued)
	testing.expect_value(t, session_key(&s, {code = protocol.KEY_CODE_LIMIT, pressed = 1, character = protocol.CHARACTER_LIMIT}), Input_Result.Queued)
}

// A move of the pointer replaces a move that still waits; a press, a key or a take by QUIC keeps it.
@(test)
a_pointer_move_replaces_the_one_that_waits :: proc(t: ^testing.T) {
	s: Session
	session_with_screen(t, &s, 8, 8, input = true)
	defer session_destroy(&s)
	pointer_size := HEADER + size_of(protocol.Pointer_Body)
	session_written(&s, len(session_outgoing(&s)))
	testing.expect_value(t, session_pointer(&s, {x = 1, y = 1}), Input_Result.Queued)
	testing.expect_value(t, session_pointer(&s, {x = 2, y = 2}), Input_Result.Queued)
	testing.expect_value(t, len(session_outgoing(&s)), pointer_size)
	testing.expect(t, strings.contains(string(session_outgoing(&s)), string(record_bytes(.Pointer, protocol.Pointer_Body{x = 2, y = 2}))))
	// Another button: a record of its own.
	testing.expect_value(t, session_pointer(&s, {x = 2, y = 2, buttons = 1}), Input_Result.Queued)
	testing.expect_value(t, len(session_outgoing(&s)), 2 * pointer_size)
	// QUIC took one byte of the last record: it no longer changes.
	session_written(&s, pointer_size + 1)
	testing.expect_value(t, session_pointer(&s, {x = 3, y = 3, buttons = 1}), Input_Result.Queued)
	testing.expect_value(t, len(session_outgoing(&s)), 2 * pointer_size - 1)
}

// The bytes of the viewer fill up with keys, and the take of a frame still has its room.
@(test)
a_full_buffer_keeps_the_room_of_the_take :: proc(t: ^testing.T) {
	s: Session
	session_with_screen(t, &s, 8, 8, input = true)
	defer session_destroy(&s)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 1, 1024)), Outcome.Taken)
	testing.expect_value(t, feed(&s, piece_bytes(0, 0, 8, 8, 0x0000_FF00)), Outcome.Taken)
	queued := 0
	for session_key(&s, {code = 0x1E, pressed = 1}) == .Queued {
		queued += 1
	}
	testing.expect(t, queued > 0)
	testing.expect_value(t, session_key(&s, {code = 0x1E, pressed = 0}), Input_Result.Full)
	before := len(session_outgoing(&s))
	testing.expect_value(t, feed(&s, record_bytes(.Viewer_Frame_End, protocol.Viewer_Frame_End_Body{serial = 1})), Outcome.Frame_Whole)
	testing.expect_value(t, len(session_outgoing(&s)), before + TAKEN_RECORD_SIZE)
}

// A whole session, byte by byte: the size, a frame of the whole screen, the pointer, then a frame of a small damage.
@(test)
a_whole_session_byte_by_byte :: proc(t: ^testing.T) {
	s: Session
	session_init(&s, false)
	defer session_destroy(&s)
	testing.expect_value(t, feed(&s, record_bytes(.Screen_Size, protocol.Screen_Size_Body{4, 2}), chunk = 1), Outcome.Screen_Size)
	whole := piece_bytes(0, 0, 4, 2, 0x0011_2233)
	testing.expect_value(t, feed(&s, frame_start_bytes(1, 1, u64(len(whole))), chunk = 1), Outcome.Taken)
	testing.expect_value(t, feed(&s, whole, chunk = 1), Outcome.Taken)
	testing.expect_value(t, feed(&s, record_bytes(.Viewer_Frame_End, protocol.Viewer_Frame_End_Body{serial = 1}), chunk = 1), Outcome.Frame_Whole)
	for pixel in s.pixels[:8] {
		testing.expect_value(t, pixel, 0x0011_2233)
	}
	testing.expect_value(t, s.damage_count, 1)
	testing.expect_value(t, s.damage[0], Rectangle{0, 0, 4, 2})
	place := protocol.Pointer_Place_Body{x = 3, y = 1, left = 2, top = 0, right = 4, bottom = 2}
	testing.expect_value(t, feed(&s, record_bytes(.Pointer_Place, place), chunk = 3), Outcome.Pointer_Moved)
	testing.expect_value(t, s.pointer, place)
	small := piece_bytes(3, 1, 1, 1, 0x00AB_CDEF)
	testing.expect_value(t, feed(&s, frame_start_bytes(2, 1, u64(len(small))), chunk = 5), Outcome.Taken)
	testing.expect_value(t, feed(&s, small, chunk = 5), Outcome.Taken)
	testing.expect_value(t, feed(&s, record_bytes(.Viewer_Frame_End, protocol.Viewer_Frame_End_Body{serial = 2}), chunk = 5), Outcome.Frame_Whole)
	testing.expect_value(t, s.pixels[7], 0x00AB_CDEF)
	testing.expect_value(t, s.pixels[6], 0x0011_2233)
	testing.expect_value(t, s.damage[0], Rectangle{3, 1, 1, 1})
	testing.expect_value(t, s.frames_whole, 2)
	// What the viewer wrote: Session_Start, then the take of each frame, in order.
	expected := append_bytes(append_bytes(
		record_bytes(.Session_Start, protocol.Session_Start_Body{version = protocol.PROTOCOL_VERSION}),
		record_bytes(.Viewer_Frame_Taken, protocol.Viewer_Frame_Taken_Body{serial = 1})),
		record_bytes(.Viewer_Frame_Taken, protocol.Viewer_Frame_Taken_Body{serial = 2}))
	testing.expect_value(t, string(session_outgoing(&s)), string(expected))
}

// The code of an end becomes its member at one place; a word past the last member, and the largest word, name none.
@(test)
a_code_of_the_machine_that_names_no_member_stays_a_word :: proc(t: ^testing.T) {
	for member in protocol.Display_Error {
		read, known := machine_code_of(u64(member))
		testing.expect(t, known)
		testing.expect_value(t, read, member)
	}
	for word in ([]u64{u64(max(protocol.Display_Error)) + 1, max(u64)}) {
		_, known := machine_code_of(word)
		testing.expect(t, !known)
	}
}
