package ecs

import "../renderer"
import "../constants"
import "core:math/linalg"

TransformComponent :: struct {
	position: linalg.Vector3f32,
	rotation: linalg.Quaternionf32,
	scale:    linalg.Vector3f32,
}

RenderComponent :: struct {
	mesh:     string,
	material: string,
	ignore_instancing: bool,
}

CameraComponent :: struct {
	offset: linalg.Vector3f32,
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

Block :: distinct constants.Block
ChunkState :: enum {
	PendingTerrain,
	DoingTerrain,

	PendingDecoration,
	DoingDecoration,

	PendingMissingBlocks,
	DoingMissingBlocks,

	PendingMesh,
	DoingMesh,
	
	Done,
	DoingDelete,
}
ChunkPos :: struct { x, y, z: i32 }
ChunkMissingBlock :: struct {
	x, y, z: i32,
	block: Block,
}
ChunkOffset :: struct {
	x, y, z: i32,
	dist_sq: i32,
}
ChunkComponent :: struct {
	palette: [dynamic]Block,
	packed_blocks: []u64,
	bits_per_block: u8,

	current_lod:  i32,
	
	state: ChunkState,

	is_empty:        bool,
	is_all_solid:    bool,

	coord: ChunkPos,
}

LightComponent :: struct {
	light_type: renderer.LightType,
	color: linalg.Vector3f32,
	direction: linalg.Vector3f32,
	intensity: f32,
	range:     f32,
}

PhysicsComponent :: struct {
	velocity: linalg.Vector3f32,
	is_grounded: bool,
	friction: f32,
}

ColliderComponent :: struct {
	size: linalg.Vector3f32,
	offset: linalg.Vector3f32,
}