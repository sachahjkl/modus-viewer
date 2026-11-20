package session

import "core:fmt"
import "modus:contract/enum_word"
import protocol "modus:contract/remote_display"

// How a connection ended (src/md/features/connection.md, "The end"). The connection thread fills it from the record of
// QUIC; the window shows its sentence.
End_Kind :: enum u8 {
	Running,               // The connection did not end.
	Closed_By_Viewer,      // The user ended the session.
	Machine_Code,          // The machine closed with an application code: End.code.
	Viewer_Refused_Record, // The session refused a record of the machine: End.refusal; the viewer closed with Bad_Record.
	Key_Not_Allowed,       // The machine refused the viewer key in the handshake: access_denied.
	Machine_Key_Differs,   // The key of the machine is not the pinned key: bad_certificate.
	No_Handshake,          // The handshake did not end before its deadline.
	Machine_Silent,        // The idle timeout of QUIC ended the connection.
	Transport_Code,        // Another code of the transport, of either side: End.code, End.by_machine.
	Address_Not_Found,     // The name of the host did not resolve.
	No_Socket,             // The system gave no UDP socket.
	Start_Refused,         // The QUIC client did not start.
}

End :: struct {
	kind:                 End_Kind,
	code:                 u64,  // Machine_Code, Transport_Code: the code of the CONNECTION_CLOSE.
	by_machine:           bool, // Transport_Code: the machine sent the code.
	// Viewer_Refused_Record: why.
	refusal:              Refusal,
	record_problem:       protocol.Record_Problem,
	screen_piece_problem: protocol.Screen_Piece_Problem,
}

// The TLS alerts that a connection to the service ends with, as the transport code 0x100 plus the alert (RFC 9001,
// section 4.8).
TLS_ALERT_ACCESS_DENIED :: 49
TLS_ALERT_BAD_CERTIFICATE :: 42

// What the machine says with each application code, after its number and its name.
@(rodata)
MACHINE_CODE_SENTENCES := [protocol.Display_Error]string {
	.None              = "the service ended the session with no fault",
	.Too_Large         = "this viewer sent a record past its bound",
	.Bad_Record        = "this viewer sent a record that the machine refused",
	.Input_Not_Allowed = "this viewer sent a key or a pointer, and the principal allowed its key for the view only; turn the input off, or allow the key with \"view_and_input\"",
	.Revoked           = "the grant of this viewer key ended: a principal revoked it, its session was locked, or another session came in front",
	.Out_Of_Order      = "this viewer took a viewer frame that was not in flight",
	.Timeout           = "this viewer did not take a viewer frame in its bound",
}

// end_sentence says how a connection ended, with its code, in one sentence.
end_sentence :: proc(end: End, allocator := context.allocator) -> string {
	switch end.kind {
	case .Running:
		return fmt.aprint("The connection runs.", allocator = allocator)
	case .Closed_By_Viewer:
		return fmt.aprint("You ended the session (code 0, None).", allocator = allocator)
	case .Machine_Code:
		// The word from the network becomes its enum here, and an unknown word stays a word.
		member, known := enum_word.member_of_word(protocol.Display_Error, end.code)
		if !known {
			return fmt.aprintf("The machine ended the session with the code %d, which this viewer does not know.", end.code, allocator = allocator)
		}
		return fmt.aprintf("The machine ended the session with the code %d (%s): %s.", end.code, protocol.DISPLAY_ERROR_NAMES[member], MACHINE_CODE_SENTENCES[member], allocator = allocator)
	case .Viewer_Refused_Record:
		why := REFUSAL_SENTENCES[end.refusal]
		#partial switch end.refusal {
		case .Record:
			why = protocol.RECORD_PROBLEM_SENTENCES[end.record_problem]
		case .Screen_Piece_Code:
			why = fmt.tprintf("a screen piece: %s", protocol.SCREEN_PIECE_PROBLEM_SENTENCES[end.screen_piece_problem])
		}
		return fmt.aprintf("This viewer refused a record of the machine and ended the session with the code %d (Bad_Record): %s.", u64(protocol.Display_Error.Bad_Record), why, allocator = allocator)
	case .Key_Not_Allowed:
		return fmt.aprintf("The machine refused this viewer key in the handshake (TLS alert %d, access_denied): no principal allowed it, or the session of its principal is locked or not in front.", TLS_ALERT_ACCESS_DENIED, allocator = allocator)
	case .Machine_Key_Differs:
		return fmt.aprintf("The machine showed another key than the machine key that you gave (TLS alert %d, bad_certificate): this viewer ended the handshake.", TLS_ALERT_BAD_CERTIFICATE, allocator = allocator)
	case .No_Handshake:
		return fmt.aprint("No machine answered the handshake before its deadline: check the address, the port and that remote_display runs. A machine that holds two viewers answers no third one.", allocator = allocator)
	case .Machine_Silent:
		return fmt.aprint("The machine stopped answering: the idle timeout of the connection passed.", allocator = allocator)
	case .Transport_Code:
		return fmt.aprintf("The connection ended with the transport code 0x%x, sent by %s.", end.code, end.by_machine ? "the machine" : "this viewer", allocator = allocator)
	case .Address_Not_Found:
		return fmt.aprint("The address names no machine that this computer can find.", allocator = allocator)
	case .No_Socket:
		return fmt.aprint("The system gave this viewer no UDP socket.", allocator = allocator)
	case .Start_Refused:
		return fmt.aprint("The QUIC client of this viewer did not start.", allocator = allocator)
	}
	return fmt.aprint("The connection ended.", allocator = allocator)
}
