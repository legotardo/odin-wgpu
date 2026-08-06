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

	chunk_size_world := f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE
	
	player_chunk_x := math.floor(player_pos.x / chunk_size_world) * chunk_size_world
	player_chunk_y := math.floor(player_pos.y / chunk_size_world) * chunk_size_world
	player_chunk_z := math.floor(player_pos.z / chunk_size_world) * chunk_size_world

	render_dist_horizontal: f32 = 4.0
	render_dist_vertical: f32 = 2.0
	
	limit_h := (render_dist_horizontal + 2.0) * chunk_size_world
	limit_v := (render_dist_vertical + 2.0) * chunk_size_world

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

			if raw_data(c.palette) != nil {
				delete(c.palette)
			}
			if raw_data(c.packed_blocks) != nil {
				delete(c.packed_blocks)
			}

			assets_unregister_mesh(&state.assets, fmt.tprintf("chunk_%f_%f_%f", t.position.x, t.position.y, t.position.z))

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
				i32(math.round(t.position.x / chunk_size_world)),
				i32(math.round(t.position.y / chunk_size_world)),
				i32(math.round(t.position.z / chunk_size_world)),
			}
			state.world.chunk_map[coord] = i
		}
	}

	chunks_created_this_frame := 0
	max_chunks_per_frame := 4

	spawn_h := int(render_dist_horizontal) + 1
	spawn_v := int(render_dist_vertical) + 1

	spawn_loop: for y := -spawn_v; y <= spawn_v; y += 1 {
		for z := -spawn_h; z <= spawn_h; z += 1 {
			for x := -spawn_h; x <= spawn_h; x += 1 {
				target_pos := linalg.Vector3f32{
					player_chunk_x + (f32(x) * chunk_size_world),
					player_chunk_y + (f32(y) * chunk_size_world),
					player_chunk_z + (f32(z) * chunk_size_world),
				}

				if world_get_chunk_at(state.world, target_pos) == -1 {
					chunk := ecs.entity_create(state.world)
					ecs.entity_add_transform(state.world, chunk, {
						position = target_pos,
						scale = {1, 1, 1},
					})
					ecs.entity_add_chunk(state.world, chunk, { state = .PendingTerrain })

					coord := [3]i32{
						i32(math.round(target_pos.x / chunk_size_world)),
						i32(math.round(target_pos.y / chunk_size_world)),
						i32(math.round(target_pos.z / chunk_size_world)),
					}
					
					idx := -1
					for e_idx in 0 ..< len(state.world.entities) {
						if state.world.entities[e_idx] == chunk {
							idx = e_idx
							break
						}
					}
					if idx != -1 {
						state.world.chunk_map[coord] = idx
					}

					chunks_created_this_frame += 1
					if chunks_created_this_frame >= max_chunks_per_frame {
						break spawn_loop
					}
				}
			}
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

		desired_lod: i32 = 1

		if chunk.state == .PendingTerrain {
			chunk.state = .DoingTerrain

			task_data := new(ChunkGenTaskData)
			task_data.world = state.world
			task_data.entity = entity
			task_data.chunk_pos = t.position
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
			task_data.chunk_pos = t.position

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_generate_decoration, task_data, 0)
			continue
		}

		if chunk.state == .PendingMesh || chunk.state == .Done {
			cam_pos := game_get_camera_eye(state)
			diff := t.position - cam_pos
			dist_sq := linalg.dot(diff, diff)

			if dist_sq > 1024*1024 {
				desired_lod = 8
			} else if dist_sq > 512*512 {
				desired_lod = 4
			} else if dist_sq > 256*256 {
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

			cs := f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE
			
			n0_idx := world_get_chunk_at(state.world, t.position + {-cs, 0  , 0})
			n1_idx := world_get_chunk_at(state.world, t.position + {cs , 0  , 0})
			n2_idx := world_get_chunk_at(state.world, t.position + {0  , -cs, 0})
			n3_idx := world_get_chunk_at(state.world, t.position + {0  , cs , 0})
			n4_idx := world_get_chunk_at(state.world, t.position + {0  , 0  , -cs})
			n5_idx := world_get_chunk_at(state.world, t.position + {0  , 0  , cs})

			n0 := n0_idx >= 0 ? &state.world.chunks[n0_idx] : nil
			n1 := n1_idx >= 0 ? &state.world.chunks[n1_idx] : nil
			n2 := n2_idx >= 0 ? &state.world.chunks[n2_idx] : nil
			n3 := n3_idx >= 0 ? &state.world.chunks[n3_idx] : nil
			n4 := n4_idx >= 0 ? &state.world.chunks[n4_idx] : nil
			n5 := n5_idx >= 0 ? &state.world.chunks[n5_idx] : nil

			if n0 == nil || n0.state <= .DoingTerrain do continue
			if n1 == nil || n1.state <= .DoingTerrain do continue
			if n2 == nil || n2.state <= .DoingTerrain do continue
			if n3 == nil || n3.state <= .DoingTerrain do continue
			if n4 == nil || n4.state <= .DoingTerrain do continue
			if n5 == nil || n5.state <= .DoingTerrain do continue

			// All solid, we dont need to fill this guy
			if chunk.is_all_solid {
				if n0.is_all_solid &&
				   n1.is_all_solid &&
				   n2.is_all_solid &&
				   n3.is_all_solid &&
				   n4.is_all_solid &&
				   n5.is_all_solid {
					chunk.state = .Done
					continue
				}
			}

			chunk.state = .DoingMesh

			task_data := new(ChunkTaskData)
			task_data.world = state.world
			task_data.entity = state.world.entities[i]
			task_data.chunk_pos = t.position
			task_data.lod = desired_lod

			task_data.neighbor_indices[0] = n0_idx
			task_data.neighbor_indices[1] = n1_idx
			task_data.neighbor_indices[2] = n2_idx
			task_data.neighbor_indices[3] = n3_idx
			task_data.neighbor_indices[4] = n4_idx
			task_data.neighbor_indices[5] = n5_idx

			if n0_idx != -1 do task_data.neighbor_entities[0] = state.world.entities[n0_idx]
			if n1_idx != -1 do task_data.neighbor_entities[1] = state.world.entities[n1_idx]
			if n2_idx != -1 do task_data.neighbor_entities[2] = state.world.entities[n2_idx]
			if n3_idx != -1 do task_data.neighbor_entities[3] = state.world.entities[n3_idx]
			if n4_idx != -1 do task_data.neighbor_entities[4] = state.world.entities[n4_idx]
			if n5_idx != -1 do task_data.neighbor_entities[5] = state.world.entities[n5_idx]

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_mesh_task, task_data, 0)
		}
	}
}
