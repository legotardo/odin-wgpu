package game

import "core:math/linalg"

Palette :: struct {
    colors: [256]linalg.Vector4f32,
}

palette_init_default :: proc() -> Palette {
    p := Palette{}

    p.colors[0] = {0, 0, 0, 0} // Nothing
    p.colors[1] = {0.247, 0.568, 0.066, 1.0} // Green 1

    return p
}