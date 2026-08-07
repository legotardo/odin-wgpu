package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:thread"
import "../constants"
import "../ecs"

// Chunk states cycle
// PendingTerrain > DoingTerrain
// PendingDecoration > DoingDecoration
// PendingMesh > DoingMesh
// Done > PendingDelete > DoingDelete

system_chunk_spawner :: proc(state: ^GameState) {
	player_pos: linalg.Vector3f32
	player_found := false

	mask_player := ecs.ComponentMask{.TransformComponent, .FirstPersonComponent}
	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask_player) == mask_player {
			player_pos = state.world.transforms[i].position
			player_found = true
			break
		}
	}

	if !player_found do return

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
			if c.state == .DoingTerrain || c.state == .DoingMesh || c.state == .DoingDecoration do continue
			c.state = .DoingDelete

			if raw_data(c.palette) != nil do delete(c.palette)
			if raw_data(c.packed_blocks) != nil do delete(c.packed_blocks)

			bx := i32(math.round(t.position.x / constants.BLOCK_SIZE))
			by := i32(math.round(t.position.y / constants.BLOCK_SIZE))
			bz := i32(math.round(t.position.z / constants.BLOCK_SIZE))

			assets_unregister_mesh(&state.assets, fmt.tprintf("chunk_%d_%d_%d", bx, by, bz))
			ecs.entity_destroy(state.world, state.world.entities[i])
		}
	}

	if state.world.chunk_map == nil {
		state.world.chunk_map = make(map[[3]i32]int, 2048)
	} else {
		clear(&state.world.chunk_map)
	}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask_chunk) == mask_chunk {
			t := &state.world.transforms[i]
			coord := [3]i32{
				i32(math.round(t.position.x / cs_world)),
				i32(math.round(t.position.y / cs_world)),
				i32(math.round(t.position.z / cs_world)),
			}
			state.world.chunk_map[coord] = i
		}
	}

	chunks_created_this_frame := 0
	max_chunks_per_frame := 4

	player_cx := i32(math.floor(player_pos.x / cs_world))
	player_cy := i32(math.floor(player_pos.y / cs_world))
	player_cz := i32(math.floor(player_pos.z / cs_world))

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
			ecs.entity_add_chunk(state.world, chunk, { state = .PendingTerrain })

			chunks_created_this_frame += 1
			if chunks_created_this_frame >= max_chunks_per_frame do break
		}
	}
}

system_chunk_generate :: proc(state: ^GameState) {
	mask := ecs.ComponentMask{.TransformComponent, .ChunkComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) != mask do continue

		entity := state.world.entities[i]
		chunk := &state.world.chunks[i]
		t := &state.world.transforms[i]
		
		bx := i32(math.round(t.position.x / constants.BLOCK_SIZE))
		by := i32(math.round(t.position.y / constants.BLOCK_SIZE))
		bz := i32(math.round(t.position.z / constants.BLOCK_SIZE))

		if chunk.state == .PendingTerrain {
			chunk.state = .DoingTerrain

			task_data := new(ChunkGenTaskData)
			task_data.world = state.world
			task_data.entity = entity
			task_data.chunk_pos = {bx, by, bz}
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
			task_data.chunk_pos = {bx, by, bz}
			task_data.terrain_node = terrain_node
			task_data.temp_node = temp_node
			task_data.humid_node = humid_node

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_generate_decoration, task_data, 0)
			continue
		} 

		desired_lod: i32 = 1
		if chunk.state == .PendingMesh || chunk.state == .Done {
			cam_pos := game_get_camera_eye(state)
			
			diff_blocks := (t.position - cam_pos) / constants.BLOCK_SIZE
			dist_sq := linalg.dot(diff_blocks, diff_blocks)

			if dist_sq > CHUNK_LOD_8_DIST {
				desired_lod = 8
			} else if dist_sq > CHUNK_LOD_4_DIST {
				desired_lod = 4
			} else if dist_sq > CHUNK_LOD_2_DIST {
				desired_lod = 2
			}
		}

		if chunk.state == .Done {
			if chunk.current_lod != desired_lod {
				chunk.current_lod = desired_lod
				chunk.state = .PendingMesh
			}
		}

		if chunk.state == .PendingMesh {
			if chunk.is_empty {
				chunk.state = .Done
				continue
			}

			cx := bx / constants.CHUNK_SIZE
			cy := by / constants.CHUNK_SIZE
			cz := bz / constants.CHUNK_SIZE

			n0_idx := world_get_chunk_at(state.world, {cx - 1, cy, cz})
			n1_idx := world_get_chunk_at(state.world, {cx + 1, cy, cz})
			n2_idx := world_get_chunk_at(state.world, {cx, cy - 1, cz})
			n3_idx := world_get_chunk_at(state.world, {cx, cy + 1, cz})
			n4_idx := world_get_chunk_at(state.world, {cx, cy, cz - 1})
			n5_idx := world_get_chunk_at(state.world, {cx, cy, cz + 1})

			n0 := n0_idx >= 0 ? &state.world.chunks[n0_idx] : nil
			n1 := n1_idx >= 0 ? &state.world.chunks[n1_idx] : nil
			n2 := n2_idx >= 0 ? &state.world.chunks[n2_idx] : nil
			n3 := n3_idx >= 0 ? &state.world.chunks[n3_idx] : nil
			n4 := n4_idx >= 0 ? &state.world.chunks[n4_idx] : nil
			n5 := n5_idx >= 0 ? &state.world.chunks[n5_idx] : nil

			if n0 == nil || n0.state <= .DoingDecoration do continue
			if n1 == nil || n1.state <= .DoingDecoration do continue
			if n2 == nil || n2.state <= .DoingDecoration do continue
			if n3 == nil || n3.state <= .DoingDecoration do continue
			if n4 == nil || n4.state <= .DoingDecoration do continue
			if n5 == nil || n5.state <= .DoingDecoration do continue

			// All solid, we dont need to fill this guy
			if chunk.is_all_solid {
				if n0.is_all_solid && n1.is_all_solid && n2.is_all_solid &&
				   n3.is_all_solid && n4.is_all_solid && n5.is_all_solid {
					chunk.state = .Done
					continue
				}
			}

			chunk.state = .DoingMesh
			task_data := new(ChunkTaskData)
			task_data.world = state.world
			task_data.entity = entity
			task_data.chunk_pos = {bx, by, bz}
			task_data.lod = desired_lod
			
			task_data.neighbor_indices = {n0_idx, n1_idx, n2_idx, n3_idx, n4_idx, n5_idx}
			if n0_idx != -1 do task_data.neighbor_entities[0] = state.world.entities[n0_idx]
			if n1_idx != -1 do task_data.neighbor_entities[1] = state.world.entities[n1_idx]
			if n2_idx != -1 do task_data.neighbor_entities[2] = state.world.entities[n2_idx]
			if n3_idx != -1 do task_data.neighbor_entities[3] = state.world.entities[n3_idx]
			if n4_idx != -1 do task_data.neighbor_entities[4] = state.world.entities[n4_idx]
			if n5_idx != -1 do task_data.neighbor_entities[5] = state.world.entities[n5_idx]

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_mesh_task, task_data, 0)
			continue
		}
	}
}