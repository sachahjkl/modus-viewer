package modus_viewer

// The keys of the toolkit as the machine reads them: the scan codes of set 1 of the keyboard of the PC, with the bit
// KEY_EXTENDED for a key that comes after the prefix 0xE0 (modus:support/display, KEY_*). A key with no code here does
// not go to the machine.

import "gt:platform"

KEY_EXTENDED :: 0x100
// The modifier bits of a Key record (modus:support/display, MODIFIER_*).
MODIFIER_SHIFT :: 1
MODIFIER_CONTROL :: 2
// The button bits of a Pointer record (modus:support/display, BUTTON_*).
BUTTON_LEFT :: 1
BUTTON_RIGHT :: 2

@(rodata)
SCAN_CODES := #partial [platform.Key]u32 {
	.A = 0x1E, .B = 0x30, .C = 0x2E, .D = 0x20, .E = 0x12, .F = 0x21, .G = 0x22, .H = 0x23, .I = 0x17, .J = 0x24,
	.K = 0x25, .L = 0x26, .M = 0x32, .N = 0x31, .O = 0x18, .P = 0x19, .Q = 0x10, .R = 0x13, .S = 0x1F, .T = 0x14,
	.U = 0x16, .V = 0x2F, .W = 0x11, .X = 0x2D, .Y = 0x15, .Z = 0x2C,
	.N1 = 0x02, .N2 = 0x03, .N3 = 0x04, .N4 = 0x05, .N5 = 0x06, .N6 = 0x07, .N7 = 0x08, .N8 = 0x09, .N9 = 0x0A, .N0 = 0x0B,
	.F1 = 0x3B, .F2 = 0x3C, .F3 = 0x3D, .F4 = 0x3E, .F5 = 0x3F, .F6 = 0x40, .F7 = 0x41, .F8 = 0x42, .F9 = 0x43,
	.F10 = 0x44, .F11 = 0x57, .F12 = 0x58,
	.Escape = 0x01, .Return = 0x1C, .Tab = 0x0F, .Space = 0x39, .Backspace = 0x0E,
	.Delete = KEY_EXTENDED | 0x53, .Insert = KEY_EXTENDED | 0x52,
	.Left = KEY_EXTENDED | 0x4B, .Right = KEY_EXTENDED | 0x4D, .Up = KEY_EXTENDED | 0x48, .Down = KEY_EXTENDED | 0x50,
	.Home = KEY_EXTENDED | 0x47, .End = KEY_EXTENDED | 0x4F, .Page_Up = KEY_EXTENDED | 0x49, .Page_Down = KEY_EXTENDED | 0x51,
	.Comma = 0x33, .Period = 0x34, .Slash = 0x35, .Minus = 0x0C, .Equal = 0x0D,
	.Shift = 0x2A, .Ctrl = 0x1D, .Alt = 0x38,
	.Menu = KEY_EXTENDED | 0x5D, .Num_Add = 0x4E, .Num_Subtract = 0x4A, .Print = KEY_EXTENDED | 0x37,
}

// scan_code_of_key gives the code of a key of the toolkit, or 0.
scan_code_of_key :: proc(key: platform.Key) -> u32 {
	return SCAN_CODES[key]
}

// scan_code_of_character gives the code of the key that types a character on a keyboard of the United States, with
// Shift or not, or 0: for a key that the toolkit does not name, and for a character that comes with no key.
scan_code_of_character :: proc(character: rune) -> u32 {
	switch character {
	case 'a' ..= 'z':
		return SCAN_CODES[platform.Key(int(platform.Key.A) + int(character - 'a'))]
	case 'A' ..= 'Z':
		return SCAN_CODES[platform.Key(int(platform.Key.A) + int(character - 'A'))]
	case '1' ..= '9':
		return 0x02 + u32(character - '1')
	case '0':
		return 0x0B
	case ' ':
		return 0x39
	case '-', '_':
		return 0x0C
	case '=', '+':
		return 0x0D
	case '[', '{':
		return 0x1A
	case ']', '}':
		return 0x1B
	case ';', ':':
		return 0x27
	case '\'', '"':
		return 0x28
	case '`', '~':
		return 0x29
	case '\\', '|':
		return 0x2B
	case ',', '<':
		return 0x33
	case '.', '>':
		return 0x34
	case '/', '?':
		return 0x35
	case '!':
		return 0x02
	case '@':
		return 0x03
	case '#':
		return 0x04
	case '$':
		return 0x05
	case '%':
		return 0x06
	case '^':
		return 0x07
	case '&':
		return 0x08
	case '*':
		return 0x09
	case '(':
		return 0x0A
	case ')':
		return 0x0B
	}
	return 0
}

// modifiers_of gives the modifier bits of a Key record. The contract carries Shift and Control only.
modifiers_of :: proc(mods: platform.Modifiers) -> u32 {
	bits: u32
	if .Shift in mods {
		bits |= MODIFIER_SHIFT
	}
	if .Ctrl in mods {
		bits |= MODIFIER_CONTROL
	}
	return bits
}

// buttons_of gives the button bits of a Pointer record. The contract carries the left and the right buttons only.
buttons_of :: proc(buttons: platform.Mouse_Buttons) -> u32 {
	bits: u32
	if .Left in buttons {
		bits |= BUTTON_LEFT
	}
	if .Right in buttons {
		bits |= BUTTON_RIGHT
	}
	return bits
}
