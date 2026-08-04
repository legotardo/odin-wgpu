package game

import "core:fmt"
import "core:thread"
import "core:math/linalg"
import "../ecs"
import "../renderer"

ChunkTaskData :: struct {
	entity: ecs.Entity,
	world: ^ecs.World,
	chunk_pos: linalg.Vector3f32,
	entity_index: int,
	neighbor_indices: [6]int,
	neighbor_entities: [6]ecs.Entity,
	vertices: []renderer.Vertex,
	indices: []u16,
	lod: i32,
}

ChunkGenTaskData :: struct {
	entity: ecs.Entity,
	world: ^ecs.World,
	chunk_pos: linalg.Vector3f32,
	entity_index: int,

	terrain_node: rawptr,
	temp_node: rawptr,
	humid_node: rawptr,
}

TASKS_LIMIT :: 500

system_resolve_thread_tasks :: proc(state: ^GameState) {
	current_tasks_count := 0

	for thread.pool_num_done(state.thread_pool) > 0 {
		task, ok := thread.pool_pop_done(state.thread_pool)
		if !ok do continue

		if task.procedure == chunk_generate_task {
			data := cast(^ChunkGenTaskData)task.data

			if data.world.entities[data.entity_index] == data.entity {
				chunk := &data.world.chunks[data.entity_index]

				chunk.is_generated = true
				chunk.is_dirty = true
				chunk.is_generating = false
			}
			free(data)
		} else if task.procedure == chunk_mesh_task {
			data := cast(^ChunkTaskData)task.data

			if data.world.entities[data.entity_index] == data.entity {
				chunk := &data.world.chunks[data.entity_index]

				if len(data.vertices) > 0 {
					mesh := renderer.mesh_create(state.renderer, data.vertices, data.indices)
					mesh_handle := assets_register_mesh(&state.assets, fmt.tprintf("chunk_%f_%f_%f", data.chunk_pos.x, data.chunk_pos.y, data.chunk_pos.z), mesh)

					ecs.entity_add_render(state.world, state.world.entities[data.entity_index], {
						mesh = string(mesh_handle),
						material = "chunk",
						ignore_instancing = true,
					})
				}

				chunk.is_dirty = false
				chunk.is_meshing = false
			}

			delete(data.vertices)
			delete(data.indices)
			free(data)
		}

		current_tasks_count += 1

		if current_tasks_count >= TASKS_LIMIT do break
	}
}