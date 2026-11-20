package layout

// The place of the floating bar (src/md/features/interface.md, "The bar"): docked to an edge, floating over the screen
// area, or solo in a window of its own. A place is a share of the room that is free for the bar, never pixels: after a
// resize, the bar is still inside the window at the same proportion.

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

Bar_Edge :: enum u8 {
	Top,
	Bottom,
	Left,
	Right,
}

// The bar along an edge. along: the share of the free run of the edge, 0 at its start (left, top), 1 at its end.
Bar_Docked :: struct {
	edge:  Bar_Edge,
	along: f32,
}

// The bar over the screen area. at: the share of the free room on each axis, 0 at the left and the top.
Bar_Floating :: struct {
	at: Vec2,
}

// A place in the window: where a solo bar comes back to.
Bar_Window_Place :: union {
	Bar_Docked,
	Bar_Floating,
}

// The bar in a window of its own.
Bar_Solo :: struct {
	back: Bar_Window_Place,
}

Bar_Place :: union {
	Bar_Docked,
	Bar_Floating,
	Bar_Solo,
}

BAR_PLACE_DEFAULT :: Bar_Docked{edge = .Top, along = 0.5}

@(rodata)
BAR_EDGE_WORDS := [Bar_Edge]string {
	.Top    = "top",
	.Bottom = "bottom",
	.Left   = "left",
	.Right  = "right",
}

// bar_place_or_default gives the default for a place that is nil.
bar_place_or_default :: proc(place: Bar_Place) -> Bar_Place {
	if place == nil {
		return BAR_PLACE_DEFAULT
	}
	return place
}

// bar_vertical says if the bar is drawn as a column: docked on a side edge.
bar_vertical :: proc(place: Bar_Place) -> bool {
	docked, is_docked := place.(Bar_Docked)
	return is_docked && (docked.edge == .Left || docked.edge == .Right)
}

// bar_rect gives the rectangle of a bar of length x thickness (along its own axis) at its place in the area, gap from
// the edges. shown is false for a solo bar: it is not in this window. A bar longer than its side is shortened to it.
bar_rect :: proc(place: Bar_Place, area: Rect, length, thickness, gap: f32) -> (rect: Rect, shown: bool) {
	width, height := area.max.x - area.min.x, area.max.y - area.min.y
	switch p in place {
	case Bar_Solo:
		return {}, false
	case Bar_Docked:
		vertical := p.edge == .Left || p.edge == .Right
		side := vertical ? height : width
		drawn := clamp(length, 0, max(side - 2 * gap, 0))
		run := max(side - 2 * gap - drawn, 0)
		position := math.floor(gap + clamp(p.along, 0, 1) * run)
		switch p.edge {
		case .Top:
			rect = rect_at({area.min.x + position, area.min.y + gap}, {drawn, thickness})
		case .Bottom:
			rect = rect_at({area.min.x + position, area.max.y - gap - thickness}, {drawn, thickness})
		case .Left:
			rect = rect_at({area.min.x + gap, area.min.y + position}, {thickness, drawn})
		case .Right:
			rect = rect_at({area.max.x - gap - thickness, area.min.y + position}, {thickness, drawn})
		}
		return rect, true
	case Bar_Floating:
		drawn := Vec2{clamp(length, 0, width), clamp(thickness, 0, height)}
		free := Vec2{width - drawn.x, height - drawn.y}
		at := Vec2{clamp(p.at.x, 0, 1), clamp(p.at.y, 0, 1)}
		return rect_at({math.floor(area.min.x + at.x * free.x), math.floor(area.min.y + at.y * free.y)}, drawn), true
	}
	// No place: the default.
	return bar_rect(BAR_PLACE_DEFAULT, area, length, thickness, gap)
}

@(private = "file")
rect_at :: proc(origin, size: Vec2) -> Rect {
	return {origin, origin + size}
}

// bar_drop gives the place of a bar released at `at`, its top-left as a horizontal bar of length x thickness, with the
// pointer at `pointer`. A pointer outside the area detaches it: solo, back at `before`. Else the nearest edge within
// `snap` docks it (top, bottom, left, right for a tie), unless the side is shorter than the vertical bar
// (vertical_length); else it floats where it was dropped.
bar_drop :: proc(at, pointer: Vec2, area: Rect, length, thickness, vertical_length, gap, snap: f32, before: Bar_Place) -> Bar_Place {
	if !inside(area, pointer) {
		return Bar_Solo{back = window_place_of(before)}
	}
	width, height := area.max.x - area.min.x, area.max.y - area.min.y
	r := rect_at(at, {length, thickness})
	distances := [Bar_Edge]f32 {
		.Top    = r.min.y - area.min.y,
		.Bottom = area.max.y - r.max.y,
		.Left   = r.min.x - area.min.x,
		.Right  = area.max.x - r.max.x,
	}
	nearest, found := Bar_Edge.Top, false
	for edge in Bar_Edge {
		if distances[edge] > snap {
			continue
		}
		vertical := edge == .Left || edge == .Right
		// A side edge shorter than the vertical bar is refused: the bar would not fit along it.
		if vertical && height - 2 * gap < vertical_length {
			continue
		}
		if !found || distances[edge] < distances[nearest] {
			nearest, found = edge, true
		}
	}
	if found {
		vertical := nearest == .Left || nearest == .Right
		side := vertical ? height : width
		docked_length := vertical ? vertical_length : length
		// On a side edge, the vertical bar is centred where the dropped bar was.
		start := vertical ? (r.min.y + r.max.y) / 2 - docked_length / 2 - area.min.y : r.min.x - area.min.x
		run := side - 2 * gap - docked_length
		along: f32 = 0.5
		if run > 0 {
			along = clamp((start - gap) / run, 0, 1)
		}
		return Bar_Docked{edge = nearest, along = along}
	}
	free := Vec2{width - length, height - thickness}
	share := Vec2{0, 0}
	if free.x > 0 {
		share.x = clamp((r.min.x - area.min.x) / free.x, 0, 1)
	}
	if free.y > 0 {
		share.y = clamp((r.min.y - area.min.y) / free.y, 0, 1)
	}
	return Bar_Floating{at = share}
}

// bar_solo_back gives the place of a solo bar whose window closed: where it was before. Another place stays.
bar_solo_back :: proc(place: Bar_Place) -> Bar_Place {
	solo, is_solo := place.(Bar_Solo)
	if !is_solo {
		return place
	}
	switch back in solo.back {
	case Bar_Docked:
		return back
	case Bar_Floating:
		return back
	}
	return BAR_PLACE_DEFAULT
}

// bar_detach makes a solo bar that comes back to the place it had.
bar_detach :: proc(place: Bar_Place) -> Bar_Place {
	if _, is_solo := place.(Bar_Solo); is_solo {
		return place
	}
	return Bar_Solo{back = window_place_of(place)}
}

@(private = "file")
window_place_of :: proc(place: Bar_Place) -> Bar_Window_Place {
	switch p in place {
	case Bar_Docked:
		return p
	case Bar_Floating:
		return p
	case Bar_Solo:
		return p.back
	}
	return BAR_PLACE_DEFAULT
}

// bar_in_zone says if the pointer asks for a bar that is not pinned: docked, the band along its edge; floating, its own
// rectangle. A solo bar is always shown, and has no zone in the window.
bar_in_zone :: proc(place: Bar_Place, area, bar: Rect, pointer: Vec2, band: f32) -> bool {
	if !inside(area, pointer) {
		return false
	}
	switch p in place {
	case Bar_Solo:
		return false
	case Bar_Floating:
		return inside(bar, pointer)
	case Bar_Docked:
		switch p.edge {
		case .Top:
			return pointer.y < area.min.y + band
		case .Bottom:
			return pointer.y >= area.max.y - band
		case .Left:
			return pointer.x < area.min.x + band
		case .Right:
			return pointer.x >= area.max.x - band
		}
	}
	return false
}

@(private = "file")
inside :: proc(r: Rect, at: Vec2) -> bool {
	return at.x >= r.min.x && at.x < r.max.x && at.y >= r.min.y && at.y < r.max.y
}

////////////////////////////////
// The place as text, in the settings: "top 0.5", "floating 0.30 0.70", "solo left 0.25"

bar_place_text :: proc(place: Bar_Place, allocator := context.allocator) -> string {
	switch p in place {
	case Bar_Docked:
		return fmt.aprintf("%s %.3f", BAR_EDGE_WORDS[p.edge], p.along, allocator = allocator)
	case Bar_Floating:
		return fmt.aprintf("floating %.3f %.3f", p.at.x, p.at.y, allocator = allocator)
	case Bar_Solo:
		back := bar_place_text(bar_solo_back(p), context.temp_allocator)
		return fmt.aprintf("solo %s", back, allocator = allocator)
	}
	return bar_place_text(BAR_PLACE_DEFAULT, allocator)
}

// bar_place_of_text reads a place. ok is false for a text that names no place: the caller takes the default. Each
// share must be a number from 0 to 1.
bar_place_of_text :: proc(text: string) -> (place: Bar_Place, ok: bool) {
	words := strings.fields(text, context.temp_allocator)
	if len(words) == 0 {
		return nil, false
	}
	if words[0] == "solo" {
		back, back_ok := bar_place_of_text(strings.join(words[1:], " ", context.temp_allocator))
		if !back_ok {
			return nil, false
		}
		if _, nested := back.(Bar_Solo); nested {
			return nil, false
		}
		return bar_detach(back), true
	}
	if words[0] == "floating" {
		if len(words) != 3 {
			return nil, false
		}
		x, x_ok := share_of(words[1])
		y, y_ok := share_of(words[2])
		if !x_ok || !y_ok {
			return nil, false
		}
		return Bar_Floating{at = {x, y}}, true
	}
	for word, edge in BAR_EDGE_WORDS {
		if words[0] != word {
			continue
		}
		if len(words) != 2 {
			return nil, false
		}
		along, along_ok := share_of(words[1])
		if !along_ok {
			return nil, false
		}
		return Bar_Docked{edge = edge, along = along}, true
	}
	return nil, false
}

@(private = "file")
share_of :: proc(word: string) -> (share: f32, ok: bool) {
	value, parsed := strconv.parse_f32(word)
	if !parsed || math.is_nan(value) || value < 0 || value > 1 {
		return 0, false
	}
	return value, true
}
