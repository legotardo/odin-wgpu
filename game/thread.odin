package game

import "core:fmt"
import "core:thread"
import "core:math/linalg"
import "../ecs"
import "../renderer"

ChunkTaskData :: struct {
    chunk: ^ecs.ChunkComponent,
	chunk_pos: linalg.Vector3f32,
	entity_index: i32,
	neighbors: [6]^ecs.ChunkComponent,
	vertices: []renderer.Vertex,
	indices: []u16,
	lod: i32,
}

ChunkGenTaskData :: struct {
	chunk: ^ecs.ChunkComponent,
	chunk_pos: linalg.Vector3f32,
	entity_index: int,
	node_tree: rawptr,
}

system_resolve_thread_tasks :: proc(state: ^GameState) {
	for thread.pool_num_done(state.thread_pool) > 0 {
		task, ok := thread.pool_pop_done(state.thread_pool)
		if !ok do continue

		if task.procedure == chunk_generate_task {
			data := cast(^ChunkGenTaskData)task.data


			data.chunk.is_generated = true
			data.chunk.is_dirty = true
			data.chunk.is_generating = false

			free(data)
		} else if task.procedure == chunk_mesh_task {
			data := cast(^ChunkTaskData)task.data

			if len(data.vertices) > 0 {
				mesh := renderer.mesh_create(state.renderer, data.vertices, data.indices)
				text := fmt.aprintf("chunk_%f_%f_%f", data.chunk_pos.x, data.chunk_pos.y, data.chunk_pos.z)
				mesh_handle := assets_register_mesh(&state.assets, text, mesh)

				ecs.entity_add_render(state.world, state.world.entities[data.entity_index], {
					mesh = string(mesh_handle),
					material = "chunk",
					ignore_instancing = true,
				})
			}

			data.chunk.is_dirty = false
			data.chunk.is_meshing = false

			delete(data.vertices)
			delete(data.indices)
			free(data)
		}
	}
}