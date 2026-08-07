package renderer

import "core:math/linalg"

LightType :: enum u32 {
	Point = 0,
	Directional = 1,
}

LightData :: struct {
	position:   linalg.Vector3f32,
	light_type: u32,
	direction:  linalg.Vector3f32,
	intensity:  f32,
	color:      linalg.Vector3f32,
	range:      f32,
}