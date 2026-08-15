package game

import "core:fmt"
import mu "vendor:microui"

import "../input"

microui_init :: proc(allocator := context.allocator) -> ^mu.Context {
    ctx := new(mu.Context)
    mu.init(ctx, os_set_clipboard, os_get_clipboard, nil)
    ctx.text_width = mu.default_atlas_text_width
    ctx.text_height = mu.default_atlas_text_height

    return ctx
}

microui_update :: proc(state: ^GameState, dt: f32) {
    microui_handle_input(state)

    ctx := state.mu_ctx
    mu.begin(ctx)

    if (mu.begin_window(ctx, "Debug", { x = 10, y = 10, w = 400, h = 300 })) {
        avg_fps := frame_stats_avg_fps(&state.frame_stats)
		low_1pct := frame_stats_1pct_low(&state.frame_stats)

        text := fmt.aprintf(
			"FPS = %d | avg = %.1f | 1%% low = %.1f | vertices = %d",
			u32(1 / dt), avg_fps, low_1pct, state.r.total_vertex_count,
		)
        defer delete(text)
        mu.label(ctx, text)
        mu.button(ctx, "Button :)", .NONE, {.ALIGN_CENTER})

        mu.end_window(ctx)
    }

    mu.end(ctx)

}

@(private="file")
microui_handle_input :: proc(state: ^GameState) {
    ctx := state.mu_ctx

    mu.input_mouse_move(ctx, i32(state.input.mouse_x), i32(state.input.mouse_y))
}

@(private="file")
os_set_clipboard :: proc(user_data: rawptr, text: string) -> (ok: bool) {
    return true
}

@(private="file")
os_get_clipboard :: proc(user_data: rawptr) -> (text: string, ok: bool) {
    return "", true
}
