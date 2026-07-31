package ecs

import "core:math/linalg"

Transform :: struct {
	position: linalg.Vector3f32,
	rotation: linalg.Vector3f32,
	scale:    linalg.Vector3f32,
}

Render :: struct {
	mesh:     string,
	material: string,
}
