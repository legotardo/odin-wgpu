package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:sync"
import "core:thread"
import "../constants"
import "../ecs"

// Chunk states cycle
// PendingTerrain > DoingTerrain
// PendingDecoration > DoingDecoration
// PendingMesh > DoingMesh
// Done > PendingDelete > DoingDelete

NEIGHBOR_OFFSETS :: [6][3]i32{ 
	{-1,  0,  0}, // n0: Left
	{ 1,  0,  0}, // n1: Right
	{ 0, -1,  0}, // n2: Bottom
	{ 0,  1,  0}, // n3: Top
	{ 0,  0, -1}, // n4: Back
	{ 0,  0,  1}, // n5: Front
}

system_chunk_spawner :: proc(state: ^GameState) {
	player_pos := state.world.transforms[state.player_idx].position
	cs_world := f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE
	
	player_chunk_x := math.floor(player_pos.x / cs_world) * cs_world
	player_chunk_y := math.floor(player_pos.y / cs_world) * cs_world
	player_chunk_z := math.floor(player_pos.z / cs_world) * cs_world
	
	limit_h := f32(state.world.render_distance + 2.0) * cs_world
	limit_v := f32(state.world.render_distance + 2.0) * cs_world

	mask_chunk := ecs.ComponentMask{.TransformComponent, .ChunkComponent}

	for i := len(state.world.entities) - 1; i >= 0; i -= 1 {
		if (state.world.masks[i] & mask_chunk) != mask_chunk do continue

		t := &state.world.transforms[i]
		
		dist_x := math.abs(t.position.x - player_chunk_x)
		dist_y := math.abs(t.position.y - player_chunk_y)
		dist_z := math.abs(t.position.z - player_chunk_z)

		c := &state.world.chunks[i]

		if dist_x > limit_h || dist_y > limit_v || dist_z > limit_h {
			if c.state == .DoingTerrain || c.state == .DoingMesh || c.state == .DoingDecoration || c.state == .DoingMissingBlocks do continue
			c.state = .DoingDelete

			if raw_data(c.palette) != nil do delete(c.palette)
			if raw_data(c.packed_blocks) != nil do delete(c.packed_blocks)

			cx := c.coord.x
			cy := c.coord.y
			cz := c.coord.z

			coord_to_remove := [3]i32{cx, cy, cz}
			delete_key(&state.world.chunk_map, coord_to_remove)

			bx := cx * constants.CHUNK_SIZE
			by := cy * constants.CHUNK_SIZE
			bz := cz * constants.CHUNK_SIZE

			assets_unregister_mesh(&state.assets, fmt.tprintf("chunk_%d_%d_%d", bx, by, bz))
			ecs.entity_destroy(state.world, state.world.entities[i])
		}
	}

	chunks_created_this_frame := 0
	max_chunks_per_frame := 4

	player_cx := i32(math.floor(player_pos.x / cs_world))
	player_cy := i32(math.floor(player_pos.y / cs_world))
	player_cz := i32(math.floor(player_pos.z / cs_world))

	prune_limit := state.world.render_distance + 2
	missing_to_prune := make([dynamic]ecs.ChunkPos, context.temp_allocator)

	sync.mutex_lock(&state.world.chunk_missing_blocks_mu)
	for coord, list in state.world.chunk_missing_blocks {
		if math.abs(coord.x - player_cx) > prune_limit ||
		   math.abs(coord.y - player_cy) > prune_limit ||
		   math.abs(coord.z - player_cz) > prune_limit {
			
			delete(list)
			append(&missing_to_prune, coord)

			if len(missing_to_prune) >= 4 { 
				break
			}
		}
	}
	
	for coord in missing_to_prune {
		delete_key(&state.world.chunk_missing_blocks, coord)
	}
	sync.mutex_unlock(&state.world.chunk_missing_blocks_mu)

	for offset in state.world.chunk_spawn_offset {
		target_coord := [3]i32{
			player_cx + offset.x,
			player_cy + offset.y,
			player_cz + offset.z,
		}

		if world_get_chunk_at(state.world, target_coord) == -1 {
			chunk := ecs.entity_create(state.world)
			ecs.entity_add_transform(state.world, chunk, {
				position = {
					f32(target_coord.x) * cs_world, 
					f32(target_coord.y) * cs_world, 
					f32(target_coord.z) * cs_world
				},
				scale = {1, 1, 1},
			})
			ecs.entity_add_chunk(state.world, chunk, { 
				state = .PendingTerrain,
				coord = {target_coord.x, target_coord.y, target_coord.z},
			})
			state.world.chunk_map[target_coord] = int(ecs.entity_index(chunk))

			chunks_created_this_frame += 1
			if chunks_created_this_frame >= max_chunks_per_frame do break
		}
	}
}

system_chunk_generate :: proc(state: ^GameState) {
	mask := ecs.ComponentMask{.TransformComponent, .ChunkComponent}
	cs_world := f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE
	cam_pos := game_get_camera_eye(state)

	for idx in state.world.active_chunks {
		chunk := &state.world.chunks[idx]
		entity := state.world.entities[idx]
		t := &state.world.transforms[idx]

		if chunk.state == .DoingTerrain ||
			chunk.state == .DoingDecoration ||
			chunk.state == .DoingMissingBlocks ||
			chunk.state == .DoingMesh || 
			chunk.state == .DoingDelete {
			continue
		}

		cx := chunk.coord.x
		cy := chunk.coord.y
		cz := chunk.coord.z

		if chunk.state == .PendingTerrain {
			chunk.state = .DoingTerrain

			task_data := new(ChunkGenTaskData)
			task_data.world = state.world
			task_data.entity = entity
			task_data.chunk_pos = {cx * constants.CHUNK_SIZE, cy * constants.CHUNK_SIZE, cz * constants.CHUNK_SIZE}
			task_data.terrain_node = terrain_node
			task_data.temp_node = temp_node
			task_data.humid_node = humid_node

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_generate_terrain, task_data, 0)
			continue
		}

		if chunk.state == .PendingDecoration {
			chunk.state = .DoingDecoration

			task_data := new(ChunkGenDecorationData)
			task_data.world = state.world
			task_data.entity = entity
			task_data.chunk_pos = {cx * constants.CHUNK_SIZE, cy * constants.CHUNK_SIZE, cz * constants.CHUNK_SIZE}
			task_data.terrain_node = terrain_node
			task_data.temp_node = temp_node
			task_data.humid_node = humid_node

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_generate_decoration, task_data, 0)
			continue
		}
	
		if chunk.state == .PendingMissingBlocks {
			neighbors_ready := true
			for offset in NEIGHBOR_OFFSETS {
				n_idx := world_get_chunk_at(state.world, {cx + offset.x, cy + offset.y, cz + offset.z})
				if n_idx >= 0 {
					n := &state.world.chunks[n_idx]
					if n.state <= .DoingDecoration {
						neighbors_ready = false
						break
					}
				}
			}

			if !neighbors_ready do continue

			chunk.state = .DoingMissingBlocks

			task_data := new(ChunkGenMissingBlocksData)
			task_data.world = state.world
			task_data.entity = entity
			task_data.chunk_pos = ecs.ChunkPos{cx, cy, cz}

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_generate_missing_blocks, task_data, 0)
			continue
		} 

		desired_lod: i32 = 1
		if chunk.state == .PendingMesh || chunk.state == .Done {
			diff_blocks := (t.position - cam_pos) / constants.BLOCK_SIZE
			dist_sq := linalg.dot(diff_blocks, diff_blocks)

			if dist_sq > constants.CHUNK_LOD_8_DIST {
				desired_lod = 8
			} else if dist_sq > constants.CHUNK_LOD_4_DIST {
				desired_lod = 4
			} else if dist_sq > constants.CHUNK_LOD_2_DIST {
				desired_lod = 2
			}
		}

		if chunk.state == .Done {
			if chunk.mesh_missing_mask != 0 {
				all_neighbors_present := true
				
				for offset, j in NEIGHBOR_OFFSETS {
					if (chunk.mesh_missing_mask & (1 << u8(j))) != 0 {
						if world_get_chunk_at(state.world, {cx + offset.x, cy + offset.y, cz + offset.z}) == -1 {
							all_neighbors_present = false
							break
						}
					}
				}

				if all_neighbors_present {
					chunk.mesh_missing_mask = 0
					chunk.state = .PendingMesh
				}
			}

			if chunk.current_lod != desired_lod {
				chunk.current_lod = desired_lod
				chunk.state = .PendingMesh
			}
		}

		if chunk.state == .PendingMesh {
			apply_missing_blocks(state.world, chunk, ecs.ChunkPos{cx, cy, cz})

			if chunk.is_empty {
				chunk.state = .Done
				continue
			}

			neighbor_indices: [6]int
			all_neighbors_solid := true
			neighbors_ready := true

			for offset, j in NEIGHBOR_OFFSETS {
				n_idx := world_get_chunk_at(state.world, {cx + offset.x, cy + offset.y, cz + offset.z})
				neighbor_indices[j] = n_idx
				
				if n_idx >= 0 {
					n := &state.world.chunks[n_idx]
					if n.state <= .DoingMissingBlocks do neighbors_ready = false
					if !n.is_all_solid do all_neighbors_solid = false
				} else {
					all_neighbors_solid = false
				}
			}

			if !neighbors_ready do continue

			if chunk.is_all_solid && all_neighbors_solid {
				chunk.state = .Done
				continue
			}

			chunk.state = .DoingMesh
			task_data := new(ChunkTaskData)
			task_data.world = state.world
			task_data.entity = entity
			task_data.chunk_pos = {cx * constants.CHUNK_SIZE, cy * constants.CHUNK_SIZE, cz * constants.CHUNK_SIZE}
			task_data.lod = desired_lod
			task_data.neighbor_indices = neighbor_indices
			
			chunk.mesh_missing_mask = 0
			for j in 0..<6 {
				if neighbor_indices[j] != -1 {
					task_data.neighbor_entities[j] = state.world.entities[neighbor_indices[j]]
				} else {
					chunk.mesh_missing_mask |= (1 << u8(j))
				}
			}

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_mesh_task, task_data, 0)
			continue
		}
	}
}