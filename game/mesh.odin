package game

import "../ecs"
import "../renderer"

MeshTaskData :: struct {
    chunk: ^ecs.ChunkComponent,
	chunk_pos: [3]f32,
	entity_index: int,
	vertices: []renderer.Vertex,
	indices: []u16,
}