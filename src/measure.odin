package modus_viewer

// The numbers behind a claim of smoothness (src/md/features/immediacy.md, "The numbers"): the frames of the machine
// that the window presented and their intervals, the frames dropped, and the round trip of QUIC. The window keeps them
// in fixed rings; `-measure` prints them at the end of the run, when no window waits for the interface thread.

import "core:fmt"
import "core:slice"
import "core:time"
import "connection"

// The intervals that -measure keeps: a session of a minute at 60 frames a second.
FRAME_INTERVAL_SAMPLES :: 4096
// The presented frames that the bar counts over the last second: more than any display shows in one second.
PRESENTED_RECENT :: 256

Measure :: struct {
	enabled:          bool, // -measure: print the lines at the end.
	presented:        u64,  // The frames of the machine that a frame of the window drew.
	dropped:          u64,  // The frames of the machine that came while the window had not taken the one before.
	last_present:     time.Tick,
	recent:           [PRESENTED_RECENT]time.Tick, // A ring of the times of the last presents, for the frames per second.
	intervals:        [FRAME_INTERVAL_SAMPLES]f32, // A ring of the intervals between two presents, in milliseconds.
	interval_count:   int,
	round_trips:      [connection.ROUND_TRIP_SAMPLES]u32, // The samples of QUIC, in microseconds, taken at the end.
	round_trip_count: int,
}

// measure_taken counts the frames that the window takes from the shared picture: the ones that it never saw are dropped.
measure_taken :: proc(m: ^Measure, seen_before, frames_now: u64) {
	if frames_now > seen_before + 1 {
		m.dropped += frames_now - seen_before - 1
	}
}

// measure_presented notes a frame of the window that drew a new frame of the machine.
measure_presented :: proc(m: ^Measure, now: time.Tick) {
	if m.presented > 0 {
		m.intervals[m.interval_count % FRAME_INTERVAL_SAMPLES] = f32(time.duration_milliseconds(time.tick_diff(m.last_present, now)))
		m.interval_count += 1
	}
	m.recent[m.presented % PRESENTED_RECENT] = now
	m.presented += 1
	m.last_present = now
}

// frames_in_last_second counts the presents of the last second before now: the frames per second of the bar.
frames_in_last_second :: proc(m: ^Measure, now: time.Tick) -> int {
	count := 0
	kept := int(min(m.presented, PRESENTED_RECENT))
	for index in 0 ..< kept {
		if time.tick_diff(m.recent[index], now) < time.Second {
			count += 1
		}
	}
	return count
}

// measure_take_round_trips copies the samples of QUIC out of the shared picture, under its lock.
measure_take_round_trips :: proc(m: ^Measure, p: ^connection.Picture) {
	m.round_trip_count = min(p.round_trip_sample_count, connection.ROUND_TRIP_SAMPLES)
	copy(m.round_trips[:m.round_trip_count], p.round_trip_samples[:m.round_trip_count])
}

// measure_print prints one line for each measure. It runs after the window closed.
measure_print :: proc(m: ^Measure) {
	if !m.enabled {
		return
	}
	if m.round_trip_count > 0 {
		samples := slice.clone(m.round_trips[:m.round_trip_count], context.temp_allocator)
		slice.sort(samples)
		fmt.printfln("modus-viewer: measure: the round trip of QUIC: least %.1f ms, median %.1f ms, of %d samples", f64(samples[0]) / 1000, f64(samples[len(samples) / 2]) / 1000, len(samples))
	} else {
		fmt.println("modus-viewer: measure: the round trip of QUIC: no sample")
	}
	count := min(m.interval_count, FRAME_INTERVAL_SAMPLES)
	if count > 0 {
		intervals := slice.clone(m.intervals[:count], context.temp_allocator)
		slice.sort(intervals)
		fmt.printfln("modus-viewer: measure: the interval between two presented frames of the machine: median %.1f ms, 95th percentile %.1f ms, of %d intervals", intervals[count / 2], intervals[min(count - 1, count * 95 / 100)], count)
	}
	fmt.printfln("modus-viewer: measure: %d frames of the machine presented, %d dropped (they came before the window took the frame before them)", m.presented, m.dropped)
	fmt.println("modus-viewer: measure: the round trip of an input to its effect: not measured: version 1 of the protocol carries no echo of the input")
}
