package renderer

import "core:math/linalg"

LightType :: enum u32 {
	Point = 0,
}

LightData :: struct {
	position:  linalg.Vector3f32,
	light_type: u32,
	color:     linalg.Vector3f32,
	intensity: f32,
	range:     f32,
	_pad1:     f32,
	_pad2:     f32,
	_pad3:     f32,
}