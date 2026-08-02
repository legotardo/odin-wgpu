package game

import "core:math"
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

    if (mu.begin_window(ctx, "Debug", { x = 10, y = 10, w = 200, h = 300 })) {
        mu.label(ctx, fmt.aprintf("FPS = %d | delta = %f", u32(1 / dt), dt))
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
