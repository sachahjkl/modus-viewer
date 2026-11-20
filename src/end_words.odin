package modus_viewer

// The sentence of each end of a connection, with its code, in the language of the user (src/md/features/connection.md,
// "The end"). The session says how a connection ended (session.End); the window says it here, where gt:i18n is.

import "core:fmt"
import i18n "gt:i18n"
import protocol "modus:contract/remote_display"
import "session"

// What the machine says with each application code, after its number and its name.
MACHINE_CODE_WORDS := [protocol.Display_Error]string {
	.None              = i18n.later("the service ended the session with no fault"),
	.Too_Large         = i18n.later("this viewer sent a record past its bound"),
	.Bad_Record        = i18n.later("this viewer sent a record that the machine refused"),
	.Input_Not_Allowed = i18n.later("this viewer sent a key or a pointer, and the principal allowed its key for the view only; turn the input off, or allow the key with \"view_and_input\""),
	.Revoked           = i18n.later("the grant of this viewer key ended: a principal revoked it, its session was locked, or another session came in front"),
	.Out_Of_Order      = i18n.later("this viewer took a viewer frame that was not in flight"),
	.Timeout           = i18n.later("this viewer did not take a viewer frame in its bound"),
}

// Why the session refused a record of the machine.
REFUSAL_WORDS := [session.Refusal]string {
	.None                        = i18n.later("the session holds"),
	.Record                      = i18n.later("the record broke a rule of the contract"),
	.Screen_Piece_Code           = i18n.later("the code of a screen piece is damaged"),
	.Frame_Before_Screen_Size    = i18n.later("a viewer frame came before the size of the screen"),
	.Screen_Size_In_Frame        = i18n.later("a size of the screen came in a viewer frame"),
	.Frame_Start_In_Frame        = i18n.later("a viewer frame started in another one"),
	.Serial_Out_Of_Order         = i18n.later("a viewer frame did not have the next serial"),
	.Piece_Outside_Frame         = i18n.later("a screen piece came outside a viewer frame"),
	.Piece_Past_Count            = i18n.later("a screen piece came past the count of its viewer frame"),
	.Piece_Past_Bytes            = i18n.later("a screen piece came past the bytes of its viewer frame"),
	.Frame_End_Outside_Frame     = i18n.later("the end of a viewer frame came outside a viewer frame"),
	.Frame_End_Other_Serial      = i18n.later("the end of a viewer frame named another viewer frame"),
	.Frame_End_Before_Last_Piece = i18n.later("a viewer frame ended before its last screen piece"),
}

// end_sentence says how a connection ended, with its code, in one sentence. The words of the contract (the name of a
// code, the problem of a record) stay as the contract writes them: they are names, which a report quotes.
end_sentence :: proc(end: session.End, allocator := context.allocator) -> string {
	switch end.kind {
	case .Running:
		return fmt.aprint(i18n.tr("The connection runs."), allocator = allocator)
	case .Closed_By_Viewer:
		return fmt.aprint(i18n.tr("You ended the session (code 0, None)."), allocator = allocator)
	case .Machine_Code:
		member, known := session.machine_code_of(end.code)
		if !known {
			return fmt.aprintf(i18n.tr("The machine ended the session with the code %d, which this viewer does not know."), end.code, allocator = allocator)
		}
		return fmt.aprintf(i18n.tr("The machine ended the session with the code %d (%s): %s."), end.code, protocol.DISPLAY_ERROR_NAMES[member], i18n.tr(MACHINE_CODE_WORDS[member]), allocator = allocator)
	case .Viewer_Refused_Record:
		why := i18n.tr(REFUSAL_WORDS[end.refusal])
		#partial switch end.refusal {
		case .Record:
			why = protocol.RECORD_PROBLEM_SENTENCES[end.record_problem]
		case .Screen_Piece_Code:
			why = fmt.tprintf(i18n.tr("a screen piece: %s"), protocol.SCREEN_PIECE_PROBLEM_SENTENCES[end.screen_piece_problem])
		}
		return fmt.aprintf(i18n.tr("This viewer refused a record of the machine and ended the session with the code %d (Bad_Record): %s."), u64(protocol.Display_Error.Bad_Record), why, allocator = allocator)
	case .Key_Not_Allowed:
		return fmt.aprintf(i18n.tr("The machine refused this viewer key in the handshake (TLS alert %d, access_denied): no principal allowed it, or the session of its principal is locked or not in front."), session.TLS_ALERT_ACCESS_DENIED, allocator = allocator)
	case .Machine_Key_Differs:
		return fmt.aprintf(i18n.tr("The machine showed another key than the machine key that you gave (TLS alert %d, bad_certificate): this viewer ended the handshake."), session.TLS_ALERT_BAD_CERTIFICATE, allocator = allocator)
	case .No_Handshake:
		return fmt.aprint(i18n.tr("No machine answered the handshake before its deadline: check the address, the port and that remote_display runs. A machine that holds two viewers answers no third one."), allocator = allocator)
	case .Machine_Silent:
		return fmt.aprint(i18n.tr("The machine stopped answering: the idle timeout of the connection passed."), allocator = allocator)
	case .Transport_Code:
		if end.by_machine {
			return fmt.aprintf(i18n.tr("The connection ended with the transport code 0x%x, sent by the machine."), end.code, allocator = allocator)
		}
		return fmt.aprintf(i18n.tr("The connection ended with the transport code 0x%x, sent by this viewer."), end.code, allocator = allocator)
	case .Address_Not_Found:
		return fmt.aprint(i18n.tr("The address names no machine that this computer can find."), allocator = allocator)
	case .No_Socket:
		return fmt.aprint(i18n.tr("The system gave this viewer no UDP socket."), allocator = allocator)
	case .No_System_Random:
		return fmt.aprint(i18n.tr("The generator of the operating system gave no random bytes: this viewer makes no connection without them."), allocator = allocator)
	case .Start_Refused:
		return fmt.aprint(i18n.tr("The QUIC client of this viewer did not start."), allocator = allocator)
	}
	return fmt.aprint(i18n.tr("The connection ended."), allocator = allocator)
}
