package session

import "modus:contract/enum_word"
import protocol "modus:contract/remote_display"

// How a connection ended (src/md/features/connection.md, "The end"). The connection thread fills it from the record of
// QUIC; the window says it in a sentence of its language (end_words.odin of the window).
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
	No_System_Random,      // The generator of the operating system gave no seed for the random generator of QUIC.
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

// machine_code_of reads the application code of an end: the word from the network becomes its enum here, at one place,
// and a word that names no member stays a word (known is false).
machine_code_of :: proc(code: u64) -> (member: protocol.Display_Error, known: bool) {
	return enum_word.member_of_word(protocol.Display_Error, code)
}
