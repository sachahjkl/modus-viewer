package modus_viewer

// The arrow of the pointer of the machine, drawn by the viewer (src/md/features/immediacy.md, "The cursor"): over the
// screen when the input is released, and in a picture with no host cursor. The platform draws no arrow of its own
// (platform.cursor_draw draws only the shapes that a system lacks), so the viewer rasterises one, once.

import "core:math"

// The design of the arrow, in units: its tip is the hotspot, at (0, 0).
@(rodata)
ARROW_OUTLINE := [?][2]f32{{0, 0}, {0, 17}, {4, 13.2}, {7, 20}, {9.6, 18.9}, {6.7, 12.2}, {12, 12.2}}
// The units of the design on each side of the picture, and the edge of the arrow in units.
ARROW_DESIGN_UNITS :: f32(21)
ARROW_EDGE_UNITS :: f32(1.3)
// The samples of a pixel on each side: 16 samples give a smooth edge with no filter.
ARROW_SAMPLES :: 4

Arrow_Picture :: struct {
	size:   int,
	pixels: []u8, // RGBA8, straight alpha.
}

// arrow_draw draws the arrow at size x size pixels: a white body in a black edge, the tip at the top left pixel.
arrow_draw :: proc(size: int, allocator := context.allocator) -> Arrow_Picture {
	picture := Arrow_Picture{size = size, pixels = make([]u8, size * size * 4, allocator)}
	unit := ARROW_DESIGN_UNITS / f32(size)
	for y in 0 ..< size {
		for x in 0 ..< size {
			body, edge := 0, 0
			for sample_y in 0 ..< ARROW_SAMPLES {
				for sample_x in 0 ..< ARROW_SAMPLES {
					point := [2]f32{(f32(x) + (f32(sample_x) + 0.5) / ARROW_SAMPLES) * unit, (f32(y) + (f32(sample_y) + 0.5) / ARROW_SAMPLES) * unit}
					inside, distance := arrow_distance(point)
					switch {
					case inside && distance > ARROW_EDGE_UNITS:
						body += 1
					case inside || distance < ARROW_EDGE_UNITS * 0.4:
						edge += 1
					}
				}
			}
			covered := body + edge
			if covered == 0 {
				continue
			}
			value := u8(255 * body / covered)
			at := (y * size + x) * 4
			picture.pixels[at], picture.pixels[at + 1], picture.pixels[at + 2] = value, value, value
			picture.pixels[at + 3] = u8(covered * 255 / (ARROW_SAMPLES * ARROW_SAMPLES))
		}
	}
	return picture
}

// arrow_distance says if a point is inside the outline (the even-odd rule), and its distance to the nearest edge.
@(private = "file")
arrow_distance :: proc(point: [2]f32) -> (inside: bool, distance: f32) {
	distance = max(f32)
	count := len(ARROW_OUTLINE)
	for index in 0 ..< count {
		start, end := ARROW_OUTLINE[index], ARROW_OUTLINE[(index + 1) % count]
		if (start.y > point.y) != (end.y > point.y) && point.x < (end.x - start.x) * (point.y - start.y) / (end.y - start.y) + start.x {
			inside = !inside
		}
		edge := end - start
		share := clamp(((point.x - start.x) * edge.x + (point.y - start.y) * edge.y) / (edge.x * edge.x + edge.y * edge.y), 0, 1)
		nearest := start + edge * share
		distance = min(distance, math.sqrt((point.x - nearest.x) * (point.x - nearest.x) + (point.y - nearest.y) * (point.y - nearest.y)))
	}
	return inside, distance
}
