package game

import "core:math/linalg"

Palette :: struct {
    colors: [256]linalg.Vector4f32,
}

palette_init_default :: proc() -> Palette {
    p := Palette{}

    p.colors[0] = {0, 0, 0, 0} // Nothing
    p.colors[1] = {0.2, 0.8, 0.2, 1.0} // Green 1
    p.colors[2] = {0.5, 0.35, 0.2, 1.0} // Brown 1

    return p
}