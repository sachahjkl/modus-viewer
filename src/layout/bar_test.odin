package layout

import "core:testing"

// The place of the bar: the edges of the snap, a side too short, a resize that would leave the bar outside, the way
// back from a solo window, and the text of the settings that names no place. The successful drops come last.

@(private = "file")
WINDOW :: Rect{{0, 0}, {1280, 800}}
@(private = "file")
LENGTH :: f32(600)
@(private = "file")
THICKNESS :: f32(40)
@(private = "file")
VERTICAL :: f32(300)
@(private = "file")
GAP :: f32(6)
@(private = "file")
SNAP :: f32(30)

@(test)
a_drop_outside_the_window_makes_a_solo_bar_that_comes_back :: proc(t: ^testing.T) {
	before := Bar_Place(Bar_Docked{edge = .Bottom, along = 0.25})
	// One pixel past the right edge and past the bottom: outside.
	for pointer in ([]Vec2{{1280, 400}, {640, 800}, {-1, 400}, {640, -1}}) {
		place := bar_drop({100, 100}, pointer, WINDOW, LENGTH, THICKNESS, VERTICAL, GAP, SNAP, before)
		solo, is_solo := place.(Bar_Solo)
		testing.expect(t, is_solo)
		testing.expect_value(t, bar_solo_back(place), before)
		_, shown := bar_rect(place, WINDOW, LENGTH, THICKNESS, GAP)
		testing.expect(t, !shown)
		testing.expect(t, solo.back != nil)
	}
	// A solo bar detached again keeps its way back; a bar that is not solo comes back as it is.
	again := bar_detach(Bar_Solo{back = Bar_Floating{at = {0.2, 0.3}}})
	testing.expect_value(t, bar_solo_back(again), Bar_Place(Bar_Floating{at = {0.2, 0.3}}))
	testing.expect_value(t, bar_solo_back(before), before)
}

@(test)
the_snap_takes_the_nearest_edge_within_its_distance :: proc(t: ^testing.T) {
	floating := Bar_Place(Bar_Floating{at = {0.5, 0.5}})
	// At the snap distance from the top: docked. One pixel further: floating.
	at_snap := bar_drop({300, SNAP}, {400, 50}, WINDOW, LENGTH, THICKNESS, VERTICAL, GAP, SNAP, floating)
	docked, is_docked := at_snap.(Bar_Docked)
	testing.expect(t, is_docked)
	testing.expect_value(t, docked.edge, Bar_Edge.Top)
	past := bar_drop({300, SNAP + 1}, {400, 50}, WINDOW, LENGTH, THICKNESS, VERTICAL, GAP, SNAP, floating)
	_, past_floats := past.(Bar_Floating)
	testing.expect(t, past_floats)
	// The bottom edge, and a tie between the top and the left: the top comes first.
	bottom := bar_drop({300, 800 - THICKNESS - 10}, {400, 780}, WINDOW, LENGTH, THICKNESS, VERTICAL, GAP, SNAP, floating)
	testing.expect_value(t, bottom.(Bar_Docked).edge, Bar_Edge.Bottom)
	tall := Rect{{0, 0}, {1280, 1000}}
	tie := bar_drop({10, 10}, {20, 20}, tall, LENGTH, THICKNESS, VERTICAL, GAP, SNAP, floating)
	testing.expect_value(t, tie.(Bar_Docked).edge, Bar_Edge.Top)
}

@(test)
a_side_shorter_than_the_vertical_bar_is_refused :: proc(t: ^testing.T) {
	floating := Bar_Place(Bar_Floating{at = {0.5, 0.5}})
	// The window is 800 high: a bar of 800 does not fit between the gaps of the left edge, so it floats.
	refused := bar_drop({5, 300}, {20, 320}, WINDOW, LENGTH, THICKNESS, 800, GAP, SNAP, floating)
	_, floats := refused.(Bar_Floating)
	testing.expect(t, floats)
	// One pixel shorter than the room of the side: docked on the left, vertical.
	fits := bar_drop({5, 300}, {20, 320}, WINDOW, LENGTH, THICKNESS, 800 - 2 * GAP, GAP, SNAP, floating)
	testing.expect_value(t, fits.(Bar_Docked).edge, Bar_Edge.Left)
	testing.expect(t, bar_vertical(fits))
	r, _ := bar_rect(fits, WINDOW, 800 - 2 * GAP, THICKNESS, GAP)
	testing.expect_value(t, r.max.x - r.min.x, THICKNESS)
}

@(test)
a_place_stays_in_the_window_after_a_resize :: proc(t: ^testing.T) {
	small := Rect{{0, 0}, {400, 300}}
	// Docked at the far end of the top: the bar is shortened to the side, and stays inside.
	end := Bar_Place(Bar_Docked{edge = .Top, along = 1})
	r, _ := bar_rect(end, small, LENGTH, THICKNESS, GAP)
	testing.expect(t, r.min.x >= small.min.x && r.max.x <= small.max.x)
	testing.expect_value(t, r.max.x - r.min.x, f32(400 - 2 * GAP))
	// Floating at the bottom right corner: inside, at its corner.
	corner := Bar_Place(Bar_Floating{at = {1, 1}})
	r, _ = bar_rect(corner, small, LENGTH, THICKNESS, GAP)
	testing.expect(t, r.min.x >= 0 && r.max.x <= 400 && r.max.y <= 300)
	// A share past its range (a place written by hand) is clamped.
	past := Bar_Place(Bar_Floating{at = {7, -3}})
	r, _ = bar_rect(past, small, 100, THICKNESS, GAP)
	testing.expect_value(t, r.min, Vec2{300, 0})
	// No place: the default, docked at the top in the middle.
	r, _ = bar_rect(nil, WINDOW, LENGTH, THICKNESS, GAP)
	testing.expect_value(t, r.min, Vec2{340, GAP})
}

@(test)
a_drop_docks_where_it_was_released :: proc(t: ^testing.T) {
	floating := Bar_Place(Bar_Floating{at = {0.5, 0.5}})
	// At the left end of the top edge, and at its right end.
	left := bar_drop({GAP, 0}, {10, 10}, WINDOW, LENGTH, THICKNESS, VERTICAL, GAP, SNAP, floating)
	testing.expect_value(t, left.(Bar_Docked).along, 0)
	right := bar_drop({1280 - GAP - LENGTH, 0}, {1270, 10}, WINDOW, LENGTH, THICKNESS, VERTICAL, GAP, SNAP, floating)
	testing.expect_value(t, right.(Bar_Docked).along, 1)
	// In the middle of the screen: floating where it was dropped, and drawn there.
	middle := bar_drop({340, 380}, {640, 400}, WINDOW, LENGTH, THICKNESS, VERTICAL, GAP, SNAP, floating)
	r, shown := bar_rect(middle, WINDOW, LENGTH, THICKNESS, GAP)
	testing.expect(t, shown)
	testing.expect_value(t, r.min, Vec2{340, 380})
}

@(test)
the_zone_of_the_bar_follows_its_place :: proc(t: ^testing.T) {
	band := f32(10)
	bottom := Bar_Place(Bar_Docked{edge = .Bottom, along = 0.5})
	r, _ := bar_rect(bottom, WINDOW, LENGTH, THICKNESS, GAP)
	testing.expect(t, bar_in_zone(bottom, WINDOW, r, {5, 795}, band))
	testing.expect(t, !bar_in_zone(bottom, WINDOW, r, {5, 5}, band))
	// Outside the window: never.
	testing.expect(t, !bar_in_zone(bottom, WINDOW, r, {5, 800}, band))
	floating := Bar_Place(Bar_Floating{at = {0.5, 0.5}})
	fr, _ := bar_rect(floating, WINDOW, LENGTH, THICKNESS, GAP)
	testing.expect(t, bar_in_zone(floating, WINDOW, fr, fr.min, band))
	testing.expect(t, !bar_in_zone(floating, WINDOW, fr, {0, 0}, band))
	testing.expect(t, !bar_in_zone(Bar_Solo{}, WINDOW, {}, {0, 0}, band))
}

@(test)
a_text_that_names_no_place_is_refused :: proc(t: ^testing.T) {
	refused := [?]string{"", "   ", "middle 0.5", "top", "top 0.5 0.5", "top 1.01", "top -0.01", "top nan", "floating 0.5", "floating 0.5 2", "solo", "solo solo top 0.5", "solo nowhere"}
	for text in refused {
		_, ok := bar_place_of_text(text)
		testing.expect(t, !ok, text)
	}
	// Each place reads back as it was written.
	places := [?]Bar_Place{Bar_Docked{edge = .Right, along = 0.25}, Bar_Floating{at = {0.125, 0.875}}, Bar_Solo{back = Bar_Docked{edge = .Left, along = 1}}, Bar_Docked{edge = .Top, along = 0}}
	for place in places {
		read, ok := bar_place_of_text(bar_place_text(place, context.temp_allocator))
		testing.expect(t, ok)
		testing.expect_value(t, read, place)
	}
}
