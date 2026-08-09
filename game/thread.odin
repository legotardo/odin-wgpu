package game

import "core:fmt"
import "core:thread"
import "core:math/linalg"
import "../ecs"
import "../renderer"
import "../shared"

ChunkTaskData :: struct {
	entity: ecs.Entity,
	world: ^ecs.World,
	chunk_pos: [3]i32,
	neighbor_indices: [6]int,
	neighbor_entities: [6]ecs.Entity,
	vertices: []renderer.Vertex,
	indices: []u16,
	lod: i32,
}

ChunkGenTaskData :: struct {
	entity: ecs.Entity,
	world: ^ecs.World,
	chunk_pos: [3]i32,

	terrain_node: rawptr,
	temp_node: rawptr,
	humid_node: rawptr,
}

ChunkGenDecorationData :: struct {
	entity: ecs.Entity,
	world: ^ecs.World,
	chunk_pos: [3]i32,

	terrain_node: rawptr,
	temp_node: rawptr,
	humid_node: rawptr,
}

ChunkGenMissingBlocksData :: struct {
	entity: ecs.Entity,
	world: ^ecs.World,
	chunk_pos: shared.ChunkPos,
}

TASKS_LIMIT :: 100

system_resolve_thread_tasks :: proc(state: ^GameState, dt: f32) {
	current_tasks_count := 0

	for thread.pool_num_done(state.thread_pool) > 0 {
		task, ok := thread.pool_pop_done(state.thread_pool)
		if !ok do continue

		switch task.procedure {
		case chunk_generate_terrain:
			data := cast(^ChunkGenTaskData)task.data
			entity_index := ecs.entity_index(data.entity)

			chunk := &data.world.chunks[entity_index]
			assert(chunk.state == .DoingTerrain)

			chunk.state = .PendingDecoration
			free(data)

		case chunk_generate_decoration:
			data := cast(^ChunkGenDecorationData)task.data
			entity_index := ecs.entity_index(data.entity)

			chunk := &data.world.chunks[entity_index]
			assert(chunk.state == .DoingDecoration)

			chunk.state = .PendingMissingBlocks
			free(data)

		case chunk_generate_missing_blocks:
			data := cast(^ChunkGenMissingBlocksData)task.data
			entity_index := ecs.entity_index(data.entity)

			chunk := &data.world.chunks[entity_index]
			assert(chunk.state == .DoingMissingBlocks)

			chunk.state = chunk.is_empty ? .Done : .PendingMesh
			free(data)

		case chunk_mesh_task:
			data := cast(^ChunkTaskData)task.data
			entity_index := ecs.entity_index(data.entity)

			chunk := &data.world.chunks[entity_index]
			assert(chunk.state == .DoingMesh)

			if len(data.vertices) > 0 {
				mesh := renderer.mesh_create(state.renderer, data.vertices, data.indices)
				mesh_handle := assets_register_mesh(&state.assets, fmt.tprintf("chunk_%d_%d_%d", data.chunk_pos.x, data.chunk_pos.y, data.chunk_pos.z), mesh)

				ecs.entity_add_render(state.world, state.world.entities[entity_index], {
					mesh = string(mesh_handle),
					material = "chunk",
					ignore_instancing = true,
				})
			}

			chunk.state = .Done

			delete(data.vertices)
			delete(data.indices)
			free(data)
		}

		current_tasks_count += 1

		if current_tasks_count >= TASKS_LIMIT do break
	}
}
