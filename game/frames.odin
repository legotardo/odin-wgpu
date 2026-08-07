package game

import "core:slice"

FRAME_HISTORY_SIZE :: 240

FrameStats :: struct {
	samples:    [FRAME_HISTORY_SIZE]f32,
	count:      int,
	head:       int,
}

frame_stats_push :: proc(stats: ^FrameStats, dt: f32) {
	stats.samples[stats.head] = dt
	stats.head = (stats.head + 1) % FRAME_HISTORY_SIZE
	if stats.count < FRAME_HISTORY_SIZE {
		stats.count += 1
	}
}

frame_stats_avg_fps :: proc(stats: ^FrameStats) -> f32 {
	if stats.count == 0 do return 0
	sum: f32 = 0
	for i in 0..<stats.count {
		sum += stats.samples[i]
	}
	avg_dt := sum / f32(stats.count)
	return 1.0 / avg_dt
}

frame_stats_1pct_low :: proc(stats: ^FrameStats) -> f32 {
	if stats.count == 0 do return 0

	sorted: [FRAME_HISTORY_SIZE]f32
	copy(sorted[:stats.count], stats.samples[:stats.count])

	slice.sort_by(sorted[:stats.count], proc(a, b: f32) -> bool { return a > b })

	worst_count := max(1, stats.count / 100)
	sum: f32 = 0
	for i in 0..<worst_count {
		sum += sorted[i]
	}
	avg_worst_dt := sum / f32(worst_count)
	return 1.0 / avg_worst_dt
}