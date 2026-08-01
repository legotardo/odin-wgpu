package game

import "../ecs"
import "../renderer"

ChunkTaskData :: struct {
    chunk: ^ecs.ChunkComponent,
	chunk_pos: [3]f32,
	entity_index: int,
	neighbors: [6]^ecs.ChunkComponent,
	vertices: []renderer.Vertex,
	indices: []u16,
}