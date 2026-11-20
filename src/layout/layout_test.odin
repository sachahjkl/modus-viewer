package layout

import "core:testing"

// The edges first: an empty area, an empty screen, the exact fit, one pixel short, the whole scales; the success last.

@(private = "file")
AREA :: Rect{{0, 0}, {1920, 1080}}

@(test)
nothing_is_placed_in_an_empty_area_or_from_an_empty_screen :: proc(t: ^testing.T) {
	_, ok := place({{0, 0}, {0, 1080}}, 1920, 1080, .Fit, {})
	testing.expect(t, !ok)
	_, ok = place({{10, 10}, {10.5, 500}}, 1920, 1080, .Fit, {})
	testing.expect(t, !ok)
	_, ok = place(AREA, 0, 1080, .Fit, {})
	testing.expect(t, !ok)
	_, ok = place(AREA, 1920, 0, .One_To_One, {})
	testing.expect(t, !ok)
}

@(test)
fit_is_one_to_one_when_the_screen_fits_and_whole_above_it :: proc(t: ^testing.T) {
	// The exact fit: 1:1, no band.
	exact, _ := place(AREA, 1920, 1080, .Fit, {})
	testing.expect_value(t, exact.scale, 1)
	testing.expect_value(t, exact.rect, AREA)
	testing.expect(t, exact.whole)
	// Just under twice the size: still 1:1, centred on whole pixels.
	under, _ := place({{0, 0}, {3839, 2159}}, 1920, 1080, .Fit, {})
	testing.expect_value(t, under.scale, 1)
	testing.expect_value(t, under.rect.min, Vec2{959, 539})
	// Twice the size, and 2.5 times: 2:1, never 2.5:1.
	twice, _ := place({{0, 0}, {3840, 2160}}, 1920, 1080, .Fit, {})
	testing.expect_value(t, twice.scale, 2)
	more, _ := place({{0, 0}, {4800, 2700}}, 1920, 1080, .Fit, {})
	testing.expect_value(t, more.scale, 2)
	testing.expect(t, more.whole)
}

@(test)
fit_keeps_the_proportions_under_one :: proc(t: ^testing.T) {
	// One pixel short in width: a filtered scale just under 1, the height follows.
	short, _ := place({{0, 0}, {1919, 1080}}, 1920, 1080, .Fit, {})
	testing.expect(t, short.scale < 1)
	testing.expect(t, !short.whole)
	testing.expect(t, abs(short.rect.max.x - short.rect.min.x - 1919) < 0.01)
	// A tall window: the width decides, the screen is centred in the height.
	tall, _ := place({{0, 0}, {960, 1080}}, 1920, 1080, .Fit, {})
	testing.expect_value(t, tall.scale, 0.5)
	testing.expect_value(t, tall.rect.min, Vec2{0, 270})
}

@(test)
one_to_one_moves_a_larger_screen_with_the_pointer :: proc(t: ^testing.T) {
	area := Rect{{0, 0}, {1280, 800}}
	at_left, _ := place(area, 1920, 1080, .One_To_One, {0, 0})
	testing.expect_value(t, at_left.rect.min, Vec2{0, 0})
	// The pointer at the far edge (and past it): the last pixels of the screen are in the window.
	at_right, _ := place(area, 1920, 1080, .One_To_One, {1280, 800})
	testing.expect_value(t, at_right.rect.min, Vec2{-640, -280})
	past, _ := place(area, 1920, 1080, .One_To_One, {5000, 5000})
	testing.expect_value(t, past.rect.min, at_right.rect.min)
	// A smaller screen is centred.
	small, _ := place(area, 640, 480, .One_To_One, {})
	testing.expect_value(t, small.rect.min, Vec2{320, 160})
}

@(test)
a_place_maps_to_its_pixel_clamped_to_the_screen :: proc(t: ^testing.T) {
	half, _ := place({{0, 0}, {960, 540}}, 1920, 1080, .Fit, {})
	area := Rect{{0, 0}, {960, 540}}
	x, y, inside := screen_pixel(half, area, {0, 0}, 1920, 1080)
	testing.expect_value(t, x, 0)
	testing.expect_value(t, y, 0)
	testing.expect(t, inside)
	// The last place of the window is the last pixel of the screen.
	x, y, inside = screen_pixel(half, area, {959.9, 539.9}, 1920, 1080)
	testing.expect_value(t, x, 1919)
	testing.expect_value(t, y, 1079)
	testing.expect(t, inside)
	// One past it, and far before it: outside, clamped to the edges.
	x, y, inside = screen_pixel(half, area, {960, 540}, 1920, 1080)
	testing.expect(t, !inside)
	testing.expect_value(t, x, 1919)
	x, y, inside = screen_pixel(half, area, {-50, -50}, 1920, 1080)
	testing.expect(t, !inside)
	testing.expect_value(t, x, 0)
	testing.expect_value(t, y, 0)
	// No placement: nothing is inside.
	_, _, inside = screen_pixel({}, area, {1, 1}, 1920, 1080)
	testing.expect(t, !inside)
}

@(test)
the_first_window_is_the_screen_when_it_fits :: proc(t: ^testing.T) {
	testing.expect_value(t, first_window_size(1920, 1080, {1920, 1080}), [2]int{1920, 1080})
	testing.expect_value(t, first_window_size(1920, 1080, {1919, 1080}), [2]int{1919, 1079})
	testing.expect_value(t, first_window_size(1920, 1080, {1280, 1280}), [2]int{1280, 720})
	// No room known (no system): the screen.
	testing.expect_value(t, first_window_size(1920, 1080, {0, 0}), [2]int{1920, 1080})
}

@(test)
the_bar_shows_after_the_dwell_and_hides_after_it :: proc(t: ^testing.T) {
	DWELL :: 300
	h: Hover
	// A button held in the band arms nothing.
	testing.expect_value(t, hover_step(&h, 0, true, false, true, DWELL), 0)
	testing.expect_value(t, h.state, Bar_Hover.Hidden)
	// In the band: armed, a wake at the dwell.
	testing.expect_value(t, hover_step(&h, 1000, true, false, false, DWELL), DWELL)
	testing.expect_value(t, h.state, Bar_Hover.Armed)
	// One millisecond before the dwell: still armed. At the dwell: shown.
	testing.expect_value(t, hover_step(&h, 1000 + DWELL - 1, true, false, false, DWELL), 1)
	testing.expect_value(t, h.state, Bar_Hover.Armed)
	hover_step(&h, 1000 + DWELL, true, false, false, DWELL)
	testing.expect_value(t, h.state, Bar_Hover.Shown)
	testing.expect(t, hover_shows_bar(h))
	// The pointer leaves: leaving, still drawn; it comes back: shown.
	hover_step(&h, 2000, false, false, false, DWELL)
	testing.expect_value(t, h.state, Bar_Hover.Leaving)
	testing.expect(t, hover_shows_bar(h))
	hover_step(&h, 2100, false, true, false, DWELL)
	testing.expect_value(t, h.state, Bar_Hover.Shown)
	// It leaves for the dwell: hidden.
	hover_step(&h, 3000, false, false, false, DWELL)
	hover_step(&h, 3000 + DWELL, false, false, false, DWELL)
	testing.expect_value(t, h.state, Bar_Hover.Hidden)
	// Armed, then out of the band before the dwell: hidden, the bar never showed.
	hover_step(&h, 4000, true, false, false, DWELL)
	hover_step(&h, 4100, false, false, false, DWELL)
	testing.expect_value(t, h.state, Bar_Hover.Hidden)
}
