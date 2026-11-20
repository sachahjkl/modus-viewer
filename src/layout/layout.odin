// The rules of the interface that need no window (src/md/features/interface.md): where the screen of the machine goes
// in the window, which pixel of the machine is under a place of the window, the first size of the window, and the
// state machine of the floating bar. Pure: the host tests drive it.
package layout

import "core:math"

Vec2 :: [2]f32

Rect :: struct {
	min, max: Vec2,
}

Scale_Mode :: enum u8 {
	Fit,        // 1:1 when the screen fits; else the largest scale that fits. A scale of 1 or more is a whole number.
	One_To_One, // Always 1:1. A screen larger than the window moves with the pointer.
}

Placement :: struct {
	rect:  Rect, // Where the screen is drawn, in pixels of the window. In One_To_One it can pass the area.
	scale: f32,
	whole: bool, // The scale is a whole number: each pixel of the machine is a block of whole pixels of the host.
}

// place puts a screen of the machine in an area of the window. pointer: the place of the host pointer, which moves a
// screen larger than the area in One_To_One. ok is false for an empty area or an empty screen.
place :: proc(area: Rect, screen_width, screen_height: u32, mode: Scale_Mode, pointer: Vec2) -> (placement: Placement, ok: bool) {
	room_width, room_height := area.max.x - area.min.x, area.max.y - area.min.y
	if room_width < 1 || room_height < 1 || screen_width == 0 || screen_height == 0 {
		return {}, false
	}
	width, height := f32(screen_width), f32(screen_height)
	scale: f32 = 1
	switch mode {
	case .One_To_One:
	case .Fit:
		fit := min(room_width / width, room_height / height)
		// Above 1, a whole scale: a pixel of the machine never spreads over a fraction of a pixel of the host.
		scale = fit >= 1 ? math.floor(fit) : fit
	}
	drawn_width, drawn_height := width * scale, height * scale
	left := axis_origin(area.min.x, room_width, drawn_width, pointer.x)
	top := axis_origin(area.min.y, room_height, drawn_height, pointer.y)
	return {rect = {{left, top}, {left + drawn_width, top + drawn_height}}, scale = scale, whole = scale >= 1 && scale == math.floor(scale)}, true
}

// axis_origin gives where the picture starts on one axis: centred when it fits, else moved so that the pointer is at the
// same share of the picture as of the room. The start is a whole pixel.
@(private = "file")
axis_origin :: proc(start, room, size, pointer: f32) -> f32 {
	if size <= room {
		return math.floor(start + (room - size) / 2)
	}
	share := clamp((pointer - start) / room, 0, 1)
	return math.floor(start - share * (size - room))
}

// screen_pixel gives the pixel of the machine under a place of the window, clamped to the screen. inside: the place is
// over the drawn screen and in the area.
screen_pixel :: proc(placement: Placement, area: Rect, at: Vec2, screen_width, screen_height: u32) -> (x, y: u32, inside: bool) {
	r := placement.rect
	if placement.scale <= 0 || screen_width == 0 || screen_height == 0 {
		return 0, 0, false
	}
	inside = at.x >= r.min.x && at.x < r.max.x && at.y >= r.min.y && at.y < r.max.y && at.x >= area.min.x && at.x < area.max.x && at.y >= area.min.y && at.y < area.max.y
	column := math.floor((at.x - r.min.x) / placement.scale)
	row := math.floor((at.y - r.min.y) / placement.scale)
	x = u32(clamp(column, 0, f32(screen_width - 1)))
	y = u32(clamp(row, 0, f32(screen_height - 1)))
	return x, y, inside
}

// first_window_size gives the size of a window for a screen of the machine: the screen itself when it fits in room,
// else the largest size with its proportions that fits. A room of zero (a window with no system) takes the screen.
first_window_size :: proc(screen_width, screen_height: u32, room: [2]int) -> [2]int {
	width, height := int(screen_width), int(screen_height)
	if room.x <= 0 || room.y <= 0 || (width <= room.x && height <= room.y) {
		return {width, height}
	}
	scale := min(f32(room.x) / f32(width), f32(room.y) / f32(height))
	// Rounded, not cut: a scale of 1919 / 1920 gives 1919 pixels, never 1918.
	return {max(int(math.round(f32(width) * scale)), 1), max(int(math.round(f32(height) * scale)), 1)}
}

////////////////////////////////
// The floating bar

Bar_Hover :: enum u8 {
	Hidden,  // The bar is not drawn.
	Armed,   // The pointer rests in the top band: the bar shows after the dwell.
	Shown,   // The bar is drawn, and the pointer is on it or in the band.
	Leaving, // The bar is drawn, and the pointer left it: it hides after the dwell, unless the pointer comes back.
}

Hover :: struct {
	state:    Bar_Hover,
	since_ms: f64,
}

// hover_step moves the state machine of the bar on the place of the pointer at now_ms. in_band: the pointer is in the
// top band of the screen area; over_bar: it is on the bar; button_down: a button of the pointer is held. It gives the
// milliseconds after which the next step is due, or 0 when none is: the caller asks the toolkit for a wake then.
hover_step :: proc(hover: ^Hover, now_ms: f64, in_band, over_bar, button_down: bool, dwell_ms: f64) -> (wake_ms: int) {
	switch hover.state {
	case .Hidden:
		if in_band && !button_down {
			hover.state, hover.since_ms = .Armed, now_ms
			return remaining(hover, now_ms, dwell_ms)
		}
	case .Armed:
		if !in_band || button_down {
			hover.state = .Hidden
			return 0
		}
		if now_ms - hover.since_ms >= dwell_ms {
			hover.state = .Shown
			return 0
		}
		return remaining(hover, now_ms, dwell_ms)
	case .Shown:
		if !over_bar && !in_band {
			hover.state, hover.since_ms = .Leaving, now_ms
			return remaining(hover, now_ms, dwell_ms)
		}
	case .Leaving:
		if over_bar || in_band {
			hover.state = .Shown
			return 0
		}
		if now_ms - hover.since_ms >= dwell_ms {
			hover.state = .Hidden
			return 0
		}
		return remaining(hover, now_ms, dwell_ms)
	}
	return 0
}

hover_shows_bar :: proc(hover: Hover) -> bool {
	return hover.state == .Shown || hover.state == .Leaving
}

@(private = "file")
remaining :: proc(hover: ^Hover, now_ms, dwell_ms: f64) -> int {
	return max(1, int(math.ceil(dwell_ms - (now_ms - hover.since_ms))))
}
