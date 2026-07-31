package ecs

import "../constants"
import "core:math/linalg"

TransformComponent :: struct {
	position: linalg.Vector3f32,
	rotation: linalg.Vector3f32,
	scale:    linalg.Vector3f32,
}

RenderComponent :: struct {
	mesh:     string,
	material: string,
}

CameraComponent :: struct {
	target: linalg.Vector3f32,
	up:     linalg.Vector3f32,
	aspect: f32,
	fovy:   f32,
	znear:  f32,
	zfar:   f32,
}

FirstPersonComponent :: struct {
	pitch:       f32,
	yaw:         f32,
	sensitivity: f32,
	speed:       f32,
}

Block :: distinct u8
ChunkComponent :: struct {
	blocks:       [constants.CHUNK_SIZE_CUBED]Block,
	is_generated: bool,
	is_dirty:     bool,
}
