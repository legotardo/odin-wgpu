package shared

import "core:math/linalg"
import "../constants"

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

BiomeType :: enum u8 {
	Desert,
	Plains,
}

BlockVariant :: struct {
	block:  Block,
	weight: int,
}

BiomeProp :: struct {
	prefab: ^VoxelPrefab,
	rarity: f32, // 0.0 - 1.0
	min_spacing: i32,
	max_per_chunk: i32,
}

BiomeConfig :: struct {
	id:                BiomeType,
	name:              string,
	surface_blocks:    []BlockVariant,
	sub_surface_block: Block,
	sub_surface_depth: i32,
	base_block:        Block,
	props: []BiomeProp,
	zenith_day: linalg.Vector3f32,
	horizon_day: linalg.Vector3f32,
}

VoxelPrefab :: struct {
    width, height, depth: i32,
    palette: []Block,
    blocks: []u8,
	min_y_offset: i32,
}