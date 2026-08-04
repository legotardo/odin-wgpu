package game

import "core:math/linalg"

import "../constants"

Palette :: struct {
    colors: [256]linalg.Vector4f32,
}

palette_init_default :: proc() -> Palette {
    p := Palette{}

    for block in constants.BLOCK_PALETTE_MAP {
        p.colors[block.key] = hex_rgb(block.value)
    }

    return p
}

hex_rgb :: #force_inline proc(color: u32) -> linalg.Vector4f32 {
    return {
        f32((color >> 16) & 0xFF) / 255.0,
        f32((color >> 8) & 0xFF) / 255.0,
        f32(color & 0xFF) / 255.0,
        1.0,
    }
}