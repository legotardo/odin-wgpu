package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:thread"
import "../constants"
import "../ecs"
import "../renderer"

system_chunk_management :: proc(state: ^GameState) {
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

				if get_chunk_at(state.world, target_pos) == -1 {
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

system_generate_chunk :: proc(state: ^GameState) {
	mask := ecs.ComponentMask{.TransformComponent, .ChunkComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) != mask do continue

		chunk := &state.world.chunks[i]
		t := &state.world.transforms[i]

		if chunk.state == .PendingTerrain {
			chunk.state = .DoingTerrain

			task_data := new(ChunkGenTaskData)
			task_data.world = state.world
			task_data.entity_index = i
			task_data.entity = state.world.entities[i]
			task_data.chunk_pos = t.position
			task_data.terrain_node = terrain_node
			task_data.temp_node = temp_node
			task_data.humid_node = humid_node

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_generate_task, task_data, 0)
			continue
		}

		if chunk.state == .PendingDecoration {
			chunk.state = .Done
			continue
		}
	}
}

system_generate_chunk_mesh :: proc(state: ^GameState) {
	mask := ecs.ComponentMask{.TransformComponent, .ChunkComponent}

	cam_pos := game_get_camera_eye(state)

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) != mask do continue

		chunk := &state.world.chunks[i]
		t := &state.world.transforms[i]
		
		diff := t.position - cam_pos
		dist_sq := linalg.dot(diff, diff)

		desired_lod: i32 = 1
		if dist_sq > 1024*1024 {
			desired_lod = 8
		} else if dist_sq > 512*512 {
			desired_lod = 4
		} else if dist_sq > 256*256 {
			desired_lod = 2
		}

		if chunk.current_lod != desired_lod && chunk.state > .DoingMesh {
			chunk.current_lod = desired_lod
			chunk.state = .PendingMesh
		}

		if chunk.state == .PendingMesh {
			if chunk.is_empty {
				chunk.state = .Done
				continue
			}

			cs := f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE
			
			n0_idx := get_chunk_at(state.world, t.position + {-cs, 0  , 0})
			n1_idx := get_chunk_at(state.world, t.position + {cs , 0  , 0})
			n2_idx := get_chunk_at(state.world, t.position + {0  , -cs, 0})
			n3_idx := get_chunk_at(state.world, t.position + {0  , cs , 0})
			n4_idx := get_chunk_at(state.world, t.position + {0  , 0  , -cs})
			n5_idx := get_chunk_at(state.world, t.position + {0  , 0  , cs})

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
			task_data.entity_index = i
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

chunk_mesh_task :: proc(t: thread.Task) {
	free_all(context.temp_allocator)

	data := cast(^ChunkTaskData)t.data

	if data.world.entities[data.entity_index] != data.entity do return

	temp_vertices, temp_indices := generate_chunk_mesh(
		data.world,
		data.entity_index,
		data.chunk_pos,
		data.neighbor_indices,
		data.neighbor_entities,
		data.lod,
	)

	data.vertices = make([]renderer.Vertex, len(temp_vertices))
	copy(data.vertices, temp_vertices)

	data.indices = make([]u16, len(temp_indices))
	copy(data.indices, temp_indices)
}

@(private = "file")
generate_chunk_mesh :: proc(
	world: ^ecs.World,
	chunk_idx: int,
	chunk_pos: linalg.Vector3f32,
	neighbor_indices: [6]int,
	neighbor_entities: [6]ecs.Entity,
	lod: i32,
) -> ([]renderer.Vertex, []u16) {
	vertices := make([dynamic]renderer.Vertex, context.temp_allocator)
	indices := make([dynamic]u16, context.temp_allocator)

	MaskData :: struct {
		block: i16,
		ao:    [4]f32,
	}

	cs_lod := (constants.CHUNK_SIZE + lod - 1) / lod
	mask := make([]MaskData, cs_lod * cs_lod, context.temp_allocator)

	for axis in 0..<3 {
		axis_u := (axis + 1) % 3
		axis_v := (axis + 2) % 3

		voxel_pos := [3]i32{0, 0, 0}
		neighbor_dir := [3]i32{0, 0, 0}
		neighbor_dir[axis] = lod

		for voxel_pos[axis] = -lod; voxel_pos[axis] < constants.CHUNK_SIZE; voxel_pos[axis] += lod {
			mask_idx: i32 = 0
			
			is_current_inside := voxel_pos[axis] >= 0
			is_neighbor_inside := (voxel_pos[axis] + lod) < constants.CHUNK_SIZE

			for v_idx in 0..<cs_lod {
				voxel_pos[axis_v] = v_idx * lod
				for u_idx in 0..<cs_lod {
					voxel_pos[axis_u] = u_idx * lod
					
					block_current := chunk_get_block(world, chunk_idx, voxel_pos[0], voxel_pos[1], voxel_pos[2], neighbor_indices, neighbor_entities)
					block_neighbor := chunk_get_block(world, chunk_idx, voxel_pos[0] + neighbor_dir[0], voxel_pos[1] + neighbor_dir[1], voxel_pos[2] + neighbor_dir[2], neighbor_indices, neighbor_entities)

					if block_current != .Air && block_neighbor == .Air && is_current_inside {
						u_dir, v_dir := [3]i32{0,0,0}, [3]i32{0,0,0}
						u_dir[axis_u] = lod
						v_dir[axis_v] = lod
						
						check_pos := voxel_pos
						check_pos[axis] += lod

						ao_bl, ao_br, ao_tr, ao_tl := sample_face_ao(world, chunk_idx, check_pos, u_dir, v_dir, neighbor_indices, neighbor_entities)

						mask[mask_idx] = MaskData{block = i16(block_current), ao = {ao_bl, ao_br, ao_tr, ao_tl}}

					} else if block_current == .Air && block_neighbor != .Air && is_neighbor_inside {
						u_dir, v_dir := [3]i32{0,0,0}, [3]i32{0,0,0}
						u_dir[axis_u] = lod
						v_dir[axis_v] = lod
						
						check_pos := voxel_pos
						
						ao_bl, ao_br, ao_tr, ao_tl := sample_face_ao(world, chunk_idx, check_pos, u_dir, v_dir, neighbor_indices, neighbor_entities)

						mask[mask_idx] = MaskData{block = -i16(block_neighbor), ao = {ao_bl, ao_br, ao_tr, ao_tl}}

					} else {
						mask[mask_idx] = MaskData{block = 0, ao = {1, 1, 1, 1}}
					}
					mask_idx += 1
				}
			}

			mask_idx = 0
			for row: i32 = 0; row < cs_lod; row += 1 {
				for col: i32 = 0; col < cs_lod; {
					if mask[mask_idx].block != 0 {
						current_mask := mask[mask_idx]

						quad_width: i32 = 1
						for col + quad_width < cs_lod && mask[mask_idx + quad_width] == current_mask {
							quad_width += 1
						}

						quad_height: i32 = 1
						outer: for row + quad_height < cs_lod {
							for check_col: i32 = 0; check_col < quad_width; check_col += 1 {
								if mask[mask_idx + check_col + quad_height * cs_lod] != current_mask {
									break outer
								}
							}
							quad_height += 1
						}

						delta_u := [3]i32{0, 0, 0}
						delta_v := [3]i32{0, 0, 0}
						delta_u[axis_u] = quad_width * lod
						delta_v[axis_v] = quad_height * lod

						quad_pos := [3]i32{0, 0, 0}
						quad_pos[axis] = voxel_pos[axis]
						quad_pos[axis_u] = col * lod
						quad_pos[axis_v] = row * lod
						quad_pos[axis] += lod

						mat_id := u8(abs(current_mask.block))
						normal_id := u8(axis * 2)
						if current_mask.block < 0 {
							normal_id += 1
						}

						bs := f32(constants.BLOCK_SIZE)

						bottom_left := renderer.Vertex{
							position = {
								(f32(quad_pos[0]) * bs) + chunk_pos.x, 
								(f32(quad_pos[1]) * bs) + chunk_pos.y, 
								(f32(quad_pos[2]) * bs) + chunk_pos.z
							},
							material_id = mat_id, normal_id = normal_id, ao = current_mask.ao[0],
						}
						bottom_right := renderer.Vertex{
							position = {
								(f32(quad_pos[0] + delta_u[0]) * bs) + chunk_pos.x, 
								(f32(quad_pos[1] + delta_u[1]) * bs) + chunk_pos.y, 
								(f32(quad_pos[2] + delta_u[2]) * bs) + chunk_pos.z
							},
							material_id = mat_id, normal_id = normal_id, ao = current_mask.ao[1],
						}
						top_right := renderer.Vertex{
							position = {
								(f32(quad_pos[0] + delta_u[0] + delta_v[0]) * bs) + chunk_pos.x, 
								(f32(quad_pos[1] + delta_u[1] + delta_v[1]) * bs) + chunk_pos.y, 
								(f32(quad_pos[2] + delta_u[2] + delta_v[2]) * bs) + chunk_pos.z
							},
							material_id = mat_id, normal_id = normal_id, ao = current_mask.ao[2],
						}
						top_left := renderer.Vertex{
							position = {
								(f32(quad_pos[0] + delta_v[0]) * bs) + chunk_pos.x, 
								(f32(quad_pos[1] + delta_v[1]) * bs) + chunk_pos.y, 
								(f32(quad_pos[2] + delta_v[2]) * bs) + chunk_pos.z
							},
							material_id = mat_id, normal_id = normal_id, ao = current_mask.ao[3],
						}

						append(&vertices, bottom_left, bottom_right, top_right, top_left)
						idx := u16(len(vertices) - 4)

						if current_mask.block > 0 {
							append(&indices, idx, idx + 1, idx + 2)
							append(&indices, idx, idx + 2, idx + 3)
						} else {
							append(&indices, idx, idx + 2, idx + 1)
							append(&indices, idx, idx + 3, idx + 2)
						}

						for clear_y: i32 = 0; clear_y < quad_height; clear_y += 1 {
							for clear_x: i32 = 0; clear_x < quad_width; clear_x += 1 {
								mask[mask_idx + clear_x + clear_y * cs_lod].block = 0
							}
						}
						col += quad_width
						mask_idx += quad_width
					} else {
						col += 1
						mask_idx += 1
					}
				}
			}
		}
	}

	return vertices[:], indices[:]
}

@(private)
chunk_get_index :: proc(x, y, z: i32) -> i32 {
	return x + (y * constants.CHUNK_SIZE) + (z * constants.CHUNK_SIZE * constants.CHUNK_SIZE)
}

@(private = "file")
chunk_get_block :: proc(world: ^ecs.World, chunk_idx: int, x, y, z: i32, neighbor_indices: [6]int, neighbor_entities: [6]ecs.Entity) -> ecs.Block {
	n_0 := neighbor_indices[0] >= 0 ? &world.chunks[neighbor_indices[0]] : nil
	n_1 := neighbor_indices[1] >= 0 ? &world.chunks[neighbor_indices[1]] : nil
	n_2 := neighbor_indices[2] >= 0 ? &world.chunks[neighbor_indices[2]] : nil
	n_3 := neighbor_indices[3] >= 0 ? &world.chunks[neighbor_indices[3]] : nil
	n_4 := neighbor_indices[4] >= 0 ? &world.chunks[neighbor_indices[4]] : nil
	n_5 := neighbor_indices[5] >= 0 ? &world.chunks[neighbor_indices[5]] : nil

	if x < 0 && n_0 != nil                     do return chunk_get_block_local(n_0, constants.CHUNK_SIZE + x, y, z)
	if x >= constants.CHUNK_SIZE && n_1 != nil do return chunk_get_block_local(n_1, x - constants.CHUNK_SIZE, y, z)

	if y < 0 && n_2 != nil                     do return chunk_get_block_local(n_2, x, constants.CHUNK_SIZE + y, z)
	if y >= constants.CHUNK_SIZE && n_3 != nil do return chunk_get_block_local(n_3, x, y - constants.CHUNK_SIZE, z)

	if z < 0 && n_4 != nil                     do return chunk_get_block_local(n_4, x, y, constants.CHUNK_SIZE + z)
	if z >= constants.CHUNK_SIZE && n_5 != nil do return chunk_get_block_local(n_5, x, y, z - constants.CHUNK_SIZE)

	return chunk_get_block_local(&world.chunks[chunk_idx], x, y, z)
}

chunk_get_block_local :: proc(chunk: ^ecs.ChunkComponent, x, y, z: i32) -> ecs.Block {
	if chunk.state == .DoingDelete do return .Air

	if x < 0 ||
	   x >= constants.CHUNK_SIZE ||
	   y < 0 ||
	   y >= constants.CHUNK_SIZE ||
	   z < 0 ||
	   z >= constants.CHUNK_SIZE {
		return .Air
	}

	if chunk.bits_per_block == 0 {
		if len(chunk.palette) == 0 do return .Air
		return chunk.palette[0]
	}

	idx := chunk_get_index(x, y, z)

	blocks_per_u64 := 64 / i32(chunk.bits_per_block)
	data_idx := idx / blocks_per_u64
	bit_offset := uint(idx % blocks_per_u64) * uint(chunk.bits_per_block)

	mask := (u64(1) << uint(chunk.bits_per_block)) - 1
	palette_idx := (chunk.packed_blocks[data_idx] >> bit_offset) & mask

	return chunk.palette[palette_idx]
}

chunk_set_block :: proc(chunk: ^ecs.ChunkComponent, x, y, z: i32, block: ecs.Block) {
	if x < 0 ||
	   x >= constants.CHUNK_SIZE ||
	   y < 0 ||
	   y >= constants.CHUNK_SIZE ||
	   z < 0 ||
	   z >= constants.CHUNK_SIZE {
		return
	}

	palette_idx := -1
	// Find the block in palette
	for p, i in chunk.palette {
		if p == block {
			palette_idx = i
			break
		}
	}

	// If block is not found, append it to the palette
	if palette_idx == -1 {
		append(&chunk.palette, block)
		palette_idx = len(chunk.palette) - 1

		chunk_repack(chunk)
	}

	if chunk.bits_per_block > 0 {
		idx := chunk_get_index(x, y, z)
		blocks_per_u64 := 64 / i32(chunk.bits_per_block)
		data_idx := idx / blocks_per_u64
		bit_offset := uint(idx % blocks_per_u64) * uint(chunk.bits_per_block)

		mask := (u64(1) << uint(chunk.bits_per_block)) - 1

		chunk.packed_blocks[data_idx] &= ~(mask << bit_offset)
		chunk.packed_blocks[data_idx] |= (u64(palette_idx) & mask) << bit_offset
	}
}

@(private = "file")
chunk_repack :: proc(chunk: ^ecs.ChunkComponent) {
	new_bits := get_required_bits(len(chunk.palette))

	if new_bits == chunk.bits_per_block do return

	old_bits := chunk.bits_per_block
	old_data := chunk.packed_blocks

	if new_bits > 0 {
		blocks_per_u64 := 64 / i32(new_bits)
		total_blocks := constants.CHUNK_SIZE_CUBED
		data_len := (total_blocks + blocks_per_u64 - 1) / blocks_per_u64

		chunk.packed_blocks = make([]u64, data_len)

		if len(old_data) > 0 {
			old_blocks_per_u64 := 64 / i32(old_bits)
			old_mask := (u64(1) << uint(old_bits)) - 1
			new_mask := (u64(1) << uint(new_bits)) - 1

			for i in 0..<total_blocks {
				old_data_idx := i / old_blocks_per_u64
				old_bit_offset := uint(i % old_blocks_per_u64) * uint(old_bits)
				palette_idx := (old_data[old_data_idx] >> old_bit_offset) & old_mask

				new_data_idx := i / blocks_per_u64
				new_bit_offset := uint(i % blocks_per_u64) * uint(new_bits)
				
				chunk.packed_blocks[new_data_idx] |= (palette_idx & new_mask) << new_bit_offset
			}

			delete(old_data)
		}
	}

	chunk.bits_per_block = new_bits
}

@(private = "file")
get_required_bits :: proc(palette_size: int) -> u8 {
	if palette_size <= 1 do return 0
	if palette_size <= 2 do return 1
	if palette_size <= 4 do return 2
	if palette_size <= 16 do return 4
	if palette_size <= 256 do return 8
	return 16
}

@(private = "file")
get_chunk_at :: proc(world: ^ecs.World, pos: linalg.Vector3f32) -> int {
	chunk_size_world := f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE
	
	coord := [3]i32{
		i32(math.round(pos.x / chunk_size_world)),
		i32(math.round(pos.y / chunk_size_world)),
		i32(math.round(pos.z / chunk_size_world)),
	}

	if idx, ok := world.chunk_map[coord]; ok {
		return idx
	}
	
	return -1
}

@(private = "file")
vertex_ao :: proc(side1, side2, corner: bool) -> f32 {
	if side1 && side2 do return 0.25
	
	s: f32 = 1.0
	if side1 do s -= 0.25
	if side2 do s -= 0.25
	if corner do s -= 0.25
	
	return s
}

@(private = "file")
sample_face_ao :: proc(
	world: ^ecs.World,
	chunk_idx: int,
	check_pos: [3]i32,
	u_dir, v_dir: [3]i32,
	neighbor_indices: [6]int,
	neighbor_entities: [6]ecs.Entity,
) -> (ao_bl, ao_br, ao_tr, ao_tl: f32) {
	side_l := chunk_get_block(world, chunk_idx, check_pos[0] - u_dir[0], check_pos[1] - u_dir[1], check_pos[2] - u_dir[2], neighbor_indices, neighbor_entities) != .Air
	side_r := chunk_get_block(world, chunk_idx, check_pos[0] + u_dir[0], check_pos[1] + u_dir[1], check_pos[2] + u_dir[2], neighbor_indices, neighbor_entities) != .Air
	side_b := chunk_get_block(world, chunk_idx, check_pos[0] - v_dir[0], check_pos[1] - v_dir[1], check_pos[2] - v_dir[2], neighbor_indices, neighbor_entities) != .Air
	side_t := chunk_get_block(world, chunk_idx, check_pos[0] + v_dir[0], check_pos[1] + v_dir[1], check_pos[2] + v_dir[2], neighbor_indices, neighbor_entities) != .Air

	corner_bl := chunk_get_block(world, chunk_idx, check_pos[0] - u_dir[0] - v_dir[0], check_pos[1] - u_dir[1] - v_dir[1], check_pos[2] - u_dir[2] - v_dir[2], neighbor_indices, neighbor_entities) != .Air
	corner_br := chunk_get_block(world, chunk_idx, check_pos[0] + u_dir[0] - v_dir[0], check_pos[1] + u_dir[1] - v_dir[1], check_pos[2] + u_dir[2] - v_dir[2], neighbor_indices, neighbor_entities) != .Air
	corner_tr := chunk_get_block(world, chunk_idx, check_pos[0] + u_dir[0] + v_dir[0], check_pos[1] + u_dir[1] + v_dir[1], check_pos[2] + u_dir[2] + v_dir[2], neighbor_indices, neighbor_entities) != .Air
	corner_tl := chunk_get_block(world, chunk_idx, check_pos[0] - u_dir[0] + v_dir[0], check_pos[1] - u_dir[1] + v_dir[1], check_pos[2] - u_dir[2] + v_dir[2], neighbor_indices, neighbor_entities) != .Air

	ao_bl = vertex_ao(side_l, side_b, corner_bl)
	ao_br = vertex_ao(side_r, side_b, corner_br)
	ao_tr = vertex_ao(side_r, side_t, corner_tr)
	ao_tl = vertex_ao(side_l, side_t, corner_tl)

	return
}

world_get_block :: proc(world: ^ecs.World, world_pos: linalg.Vector3f32) -> ecs.Block {
	chunk_size_world := f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE

	chunk_x := math.floor(world_pos.x / chunk_size_world) * chunk_size_world
	chunk_y := math.floor(world_pos.y / chunk_size_world) * chunk_size_world
	chunk_z := math.floor(world_pos.z / chunk_size_world) * chunk_size_world

	chunk_pos := linalg.Vector3f32{chunk_x, chunk_y, chunk_z}

	chunk_idx := get_chunk_at(world, chunk_pos)
	if chunk_idx == -1 do return .Air

	local_x := i32(math.floor((world_pos.x - chunk_x) / constants.BLOCK_SIZE))
	local_y := i32(math.floor((world_pos.y - chunk_y) / constants.BLOCK_SIZE))
	local_z := i32(math.floor((world_pos.z - chunk_z) / constants.BLOCK_SIZE))

	return chunk_get_block_local(&world.chunks[chunk_idx], local_x, local_y, local_z)
}

world_check_collision :: proc(world: ^ecs.World, aabb: AABB) -> bool {
	min_x := i32(math.floor(aabb.min.x / constants.BLOCK_SIZE))
	max_x := i32(math.floor(aabb.max.x / constants.BLOCK_SIZE))
	min_y := i32(math.floor(aabb.min.y / constants.BLOCK_SIZE))
	max_y := i32(math.floor(aabb.max.y / constants.BLOCK_SIZE))
	min_z := i32(math.floor(aabb.min.z / constants.BLOCK_SIZE))
	max_z := i32(math.floor(aabb.max.z / constants.BLOCK_SIZE))

	for y in min_y ..= max_y {
		for z in min_z ..= max_z {
			for x in min_x ..= max_x {
				world_pos := linalg.Vector3f32{
					f32(x) * constants.BLOCK_SIZE,
					f32(y) * constants.BLOCK_SIZE,
					f32(z) * constants.BLOCK_SIZE,
				}

				block := world_get_block(world, world_pos)
				if block != .Air {
					return true
				}
			}
		}
	}

	return false
}

@(private = "file")
stamp_prefab :: proc(chunk: ^ecs.ChunkComponent, prefab: ^VoxelPrefab,
	world_position: linalg.Vector3f32,
	chunk_base: linalg.Vector3f32,
) -> i32 {
	local_start_x := i32(world_position.x - chunk_base.x)
	local_start_y := i32(world_position.y - chunk_base.y)
	local_start_z := i32(world_position.z - chunk_base.z)

	blocks_stamped: i32 = 0

	palette_remap := make([]int, len(prefab.palette), context.temp_allocator)
	for i in 0..<len(palette_remap) {
		palette_remap[i] = -1
	}
	for p_block, p_idx in prefab.palette {
		palette_remap[p_idx] = chunk_get_or_add_palette_idx(chunk, p_block)
	}

	for py in 0 ..< prefab.height {
		for pz in 0 ..< prefab.depth {
			for px in 0 ..< prefab.width {
				cx := local_start_x + px
				cy := local_start_y + py
				cz := local_start_z + pz

				if cx < 0 || cx >= constants.CHUNK_SIZE ||
				   cy < 0 || cy >= constants.CHUNK_SIZE ||
				   cz < 0 || cz >= constants.CHUNK_SIZE {
					continue
				}

				idx := px + (py * prefab.width) + (pz * prefab.width * prefab.height)
				vox_color_index := prefab.blocks[idx]
				
				if vox_color_index == 0 do continue 

				if palette_remap[vox_color_index] == -1 {
					real_block := prefab.palette[vox_color_index]
					palette_remap[vox_color_index] = chunk_get_or_add_palette_idx(chunk, real_block)
				}

				target_palette_idx := palette_remap[vox_color_index]
				
				chunk_set_block_fast(chunk, cx, cy, cz, target_palette_idx)
				blocks_stamped += 1
			}
		}
	}

	return blocks_stamped
}

@(private = "file")
chunk_get_or_add_palette_idx :: proc(chunk: ^ecs.ChunkComponent, block: ecs.Block) -> int {
	for p, i in chunk.palette {
		if p == block do return i
	}
	
	append(&chunk.palette, block)
	chunk_repack(chunk)
	
	return len(chunk.palette) - 1
}

@(private = "file")
chunk_set_block_fast :: proc(chunk: ^ecs.ChunkComponent, x, y, z: i32, palette_idx: int) {
	if chunk.bits_per_block > 0 {
		idx := chunk_get_index(x, y, z)
		blocks_per_u64 := 64 / i32(chunk.bits_per_block)
		data_idx := idx / blocks_per_u64
		bit_offset := uint(idx % blocks_per_u64) * uint(chunk.bits_per_block)

		mask := (u64(1) << uint(chunk.bits_per_block)) - 1

		chunk.packed_blocks[data_idx] &= ~(mask << bit_offset)
		chunk.packed_blocks[data_idx] |= (u64(palette_idx) & mask) << bit_offset
	}
}