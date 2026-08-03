package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:thread"
import "../constants"
import "../ecs"
import "../renderer"
import "../libs/fast_noise"

terrain_node := fast_noise.NewFromEncodedNodeTree("DQAH@BC@AIEAJBw@ABZEED0KV78YZmZmPwQDmpkZPwsAAIA/BA==", transmute(u32)~u32(0))

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
	
	limit_h := render_dist_horizontal * chunk_size_world
	limit_v := render_dist_vertical * 6

	mask_chunk := ecs.ComponentMask{.TransformComponent, .ChunkComponent}
	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask_chunk) != mask_chunk do continue

		t := &state.world.transforms[i]
		
		dist_x := math.abs(t.position.x - player_chunk_x)
		dist_y := math.abs(t.position.y - player_chunk_y)
		dist_z := math.abs(t.position.z - player_chunk_z)

		if dist_x > limit_h || dist_y > limit_v || dist_z > limit_h {
			ecs.entity_destroy(state.world, ecs.Entity(i))
		}
	}

	chunks_created_this_frame := 0
	max_chunks_per_frame := 2

	spawn_loop: for y := -int(render_dist_vertical); y <= int(render_dist_vertical); y += 1 {
		for z := -int(render_dist_horizontal); z <= int(render_dist_horizontal); z += 1 {
			for x := -int(render_dist_horizontal); x <= int(render_dist_horizontal); x += 1 {
				target_pos := linalg.Vector3f32{
					player_chunk_x + (f32(x) * chunk_size_world),
					player_chunk_y + (f32(y) * chunk_size_world),
					player_chunk_z + (f32(z) * chunk_size_world),
				}

				if get_chunk_at(state.world, target_pos) == nil {
					chunk := ecs.entity_create(state.world)
					ecs.entity_add_transform(state.world, chunk, {
						position = target_pos,
						scale = {1, 1, 1},
					})
					ecs.entity_add_chunk(state.world, chunk, {})

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

		if !chunk.is_generated && !chunk.is_generating {
			chunk.is_generating = true

			task_data := new(ChunkGenTaskData)
			task_data.chunk = chunk
			task_data.chunk_pos = t.position
			task_data.entity_index = i
			task_data.node_tree = terrain_node

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_generate_task, task_data, 0)
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
		
		dist := linalg.distance(t.position, cam_pos)

		desired_lod: i32 = 1
		if dist > 1024 {
			desired_lod = 8
		} else if dist > 512 {
			desired_lod = 4
		} else if dist > 256 {
			desired_lod = 2
		}

		if chunk.current_lod != desired_lod {
			chunk.current_lod = desired_lod
			chunk.is_dirty = true
		}

		if chunk.is_generated && chunk.is_dirty && !chunk.is_meshing {
			if chunk.is_empty {
				chunk.is_meshing = false
				chunk.is_dirty = false
				continue
			}

			cs := f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE
			
			n0 := get_chunk_at(state.world, t.position + {-cs, 0  , 0})
			n1 := get_chunk_at(state.world, t.position + {cs , 0  , 0})
			n2 := get_chunk_at(state.world, t.position + {0  , -cs, 0})
			n3 := get_chunk_at(state.world, t.position + {0  , cs , 0})
			n4 := get_chunk_at(state.world, t.position + {0  , 0  , -cs})
			n5 := get_chunk_at(state.world, t.position + {0  , 0  , cs})

			neighbors_ready := true
			if n0 != nil && !n0.is_generated do neighbors_ready = false
			if n1 != nil && !n1.is_generated do neighbors_ready = false
			if n2 != nil && !n2.is_generated do neighbors_ready = false
			if n3 != nil && !n3.is_generated do neighbors_ready = false
			if n4 != nil && !n4.is_generated do neighbors_ready = false
			if n5 != nil && !n5.is_generated do neighbors_ready = false

			if !neighbors_ready do continue

			if chunk.is_all_solid {
				is_hidden := true
				
				if n0 != nil && !n0.is_all_solid do is_hidden = false
				if n1 != nil && !n1.is_all_solid do is_hidden = false
				if n2 != nil && !n2.is_all_solid do is_hidden = false
				if n3 != nil && !n3.is_all_solid do is_hidden = false
				if n4 != nil && !n4.is_all_solid do is_hidden = false
				if n5 != nil && !n5.is_all_solid do is_hidden = false
				
				if is_hidden {
					chunk.is_meshing = false
					chunk.is_dirty = false
					continue
				}
			}

			chunk.is_meshing = true

			task_data := new(ChunkTaskData)
			task_data.chunk = chunk
			task_data.chunk_pos = t.position
			task_data.entity_index = i
			task_data.lod = desired_lod

			task_data.neighbors[0] = n0
			task_data.neighbors[1] = n1
			task_data.neighbors[2] = n2
			task_data.neighbors[3] = n3
			task_data.neighbors[4] = n4
			task_data.neighbors[5] = n5

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_mesh_task, task_data, 0)
		}
	}
}

chunk_generate_task :: proc(t: thread.Task) {
	defer free_all(context.temp_allocator)
	data := cast(^ChunkGenTaskData)t.data

	if len(data.chunk.palette) == 0 {
		append(&data.chunk.palette, 0)
	}

	seed: i32 = 12345

	chunk_size := constants.CHUNK_SIZE
	block_size := constants.BLOCK_SIZE
	noise_buffer := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)
	start_x := f32(math.round(data.chunk_pos.x / block_size))
	start_z := f32(math.round(data.chunk_pos.z / block_size))

	chunk_block_y := i32(math.round(data.chunk_pos.y / block_size))

	fast_noise.GenUniformGrid2D(
		data.node_tree,
		raw_data(noise_buffer),
		start_x, start_z,
		chunk_size, chunk_size,
		1,
		1,
		seed,
		nil
	)

	BASE_HEIGHT: f32 = 64.0
	HEIGHT_AMPLITUDE: f32 = 48.0
	blocks_placed: i32 = 0

	for z in 0 ..< chunk_size {
		for x in 0 ..< chunk_size {

			terrain_height_raw := noise_buffer[z * chunk_size + x]
			world_surface_y := BASE_HEIGHT + (terrain_height_raw * HEIGHT_AMPLITUDE)
			surface_block_y := i32(world_surface_y)

			for y in 0 ..< chunk_size {
				world_block_y := chunk_block_y + y

				if world_block_y < surface_block_y {
					chunk_set_block(data.chunk, x, y, z, 1)
					blocks_placed += 1
				}
			}
		}
	}

	max_blocks := chunk_size * chunk_size * chunk_size
	if blocks_placed == 0 {
		data.chunk.is_empty = true
	} else if blocks_placed == max_blocks {
		data.chunk.is_all_solid = true
	}
}

chunk_mesh_task :: proc(t: thread.Task) {
	defer free_all(context.temp_allocator)
	data := cast(^ChunkTaskData)t.data

	temp_vertices, temp_indices := generate_chunk_mesh(
		data.chunk,
		data.chunk_pos,
		data.neighbors,
		data.lod,
	)

	data.vertices = make([]renderer.Vertex, len(temp_vertices))
	copy(data.vertices, temp_vertices)

	data.indices = make([]u16, len(temp_indices))
	copy(data.indices, temp_indices)

	free_all(context.temp_allocator)
}

@(private = "file")
generate_chunk_mesh :: proc(
	chunk: ^ecs.ChunkComponent,
	chunk_pos: linalg.Vector3f32,
	neighbors: [6]^ecs.ChunkComponent,
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
					
					block_current := chunk_get_block(chunk, voxel_pos[0], voxel_pos[1], voxel_pos[2], neighbors)
					block_neighbor := chunk_get_block(chunk, voxel_pos[0] + neighbor_dir[0], voxel_pos[1] + neighbor_dir[1], voxel_pos[2] + neighbor_dir[2], neighbors)

					if block_current != 0 && block_neighbor == 0 && is_current_inside {
						u_dir, v_dir := [3]i32{0,0,0}, [3]i32{0,0,0}
						u_dir[axis_u] = lod
						v_dir[axis_v] = lod
						
						check_pos := voxel_pos
						check_pos[axis] += lod

						ao_bl, ao_br, ao_tr, ao_tl := sample_face_ao(chunk, check_pos, u_dir, v_dir, neighbors)

						mask[mask_idx] = MaskData{block = i16(block_current), ao = {ao_bl, ao_br, ao_tr, ao_tl}}

					} else if block_current == 0 && block_neighbor != 0 && is_neighbor_inside {
						u_dir, v_dir := [3]i32{0,0,0}, [3]i32{0,0,0}
						u_dir[axis_u] = lod
						v_dir[axis_v] = lod
						
						check_pos := voxel_pos
						
						ao_bl, ao_br, ao_tr, ao_tl := sample_face_ao(chunk, check_pos, u_dir, v_dir, neighbors)

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
chunk_get_block :: proc(chunk: ^ecs.ChunkComponent, x, y, z: i32, neighbors: [6]^ecs.ChunkComponent) -> ecs.Block {
	if x < 0 {
		if neighbors[0] == nil do return 0
		return chunk_get_block_local(neighbors[0], constants.CHUNK_SIZE + x, y, z)
	} else if x >= constants.CHUNK_SIZE {
		if neighbors[1] == nil do return 0
		return chunk_get_block_local(neighbors[1], x - constants.CHUNK_SIZE, y, z)
	} else if y < 0 {
		if neighbors[2] == nil do return 1
		return chunk_get_block_local(neighbors[2], x, constants.CHUNK_SIZE + y, z)
	} else if y >= constants.CHUNK_SIZE {
		if neighbors[3] == nil do return 0
		return chunk_get_block_local(neighbors[3], x, y - constants.CHUNK_SIZE, z)
	} else if z < 0 {
		if neighbors[4] == nil do return 0
		return chunk_get_block_local(neighbors[4], x, y, constants.CHUNK_SIZE + z)
	} else if z >= constants.CHUNK_SIZE {
		if neighbors[5] == nil do return 0
		return chunk_get_block_local(neighbors[5], x, y, z - constants.CHUNK_SIZE)
	}

	return chunk_get_block_local(chunk, x, y, z)
}

chunk_get_block_local :: proc(chunk: ^ecs.ChunkComponent, x, y, z: i32) -> ecs.Block {
	if x < 0 ||
	   x >= constants.CHUNK_SIZE ||
	   y < 0 ||
	   y >= constants.CHUNK_SIZE ||
	   z < 0 ||
	   z >= constants.CHUNK_SIZE {
		return 0
	}

	if chunk.bits_per_block == 0 {
		if len(chunk.palette) == 0 do return 0
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

@(private = "file")
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
	for p, i in chunk.palette {
		if p == block {
			palette_idx = i
			break
		}
	}

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
get_chunk_at :: proc(world: ^ecs.World, pos: linalg.Vector3f32) -> ^ecs.ChunkComponent {
	mask := ecs.ComponentMask{.TransformComponent, .ChunkComponent}

	for i in 0..< len(world.entities) {
		if (world.masks[i] & mask) != mask do continue

		if world.transforms[i].position == pos {
			return &world.chunks[i]
		}
	}
	
	return nil
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
	chunk: ^ecs.ChunkComponent,
	check_pos: [3]i32,
	u_dir, v_dir: [3]i32,
	neighbors: [6]^ecs.ChunkComponent,
) -> (ao_bl, ao_br, ao_tr, ao_tl: f32) {
	side_l := chunk_get_block(chunk, check_pos[0] - u_dir[0], check_pos[1] - u_dir[1], check_pos[2] - u_dir[2], neighbors) != 0
	side_r := chunk_get_block(chunk, check_pos[0] + u_dir[0], check_pos[1] + u_dir[1], check_pos[2] + u_dir[2], neighbors) != 0
	side_b := chunk_get_block(chunk, check_pos[0] - v_dir[0], check_pos[1] - v_dir[1], check_pos[2] - v_dir[2], neighbors) != 0
	side_t := chunk_get_block(chunk, check_pos[0] + v_dir[0], check_pos[1] + v_dir[1], check_pos[2] + v_dir[2], neighbors) != 0

	corner_bl := chunk_get_block(chunk, check_pos[0] - u_dir[0] - v_dir[0], check_pos[1] - u_dir[1] - v_dir[1], check_pos[2] - u_dir[2] - v_dir[2], neighbors) != 0
	corner_br := chunk_get_block(chunk, check_pos[0] + u_dir[0] - v_dir[0], check_pos[1] + u_dir[1] - v_dir[1], check_pos[2] + u_dir[2] - v_dir[2], neighbors) != 0
	corner_tr := chunk_get_block(chunk, check_pos[0] + u_dir[0] + v_dir[0], check_pos[1] + u_dir[1] + v_dir[1], check_pos[2] + u_dir[2] + v_dir[2], neighbors) != 0
	corner_tl := chunk_get_block(chunk, check_pos[0] - u_dir[0] + v_dir[0], check_pos[1] - u_dir[1] + v_dir[1], check_pos[2] - u_dir[2] + v_dir[2], neighbors) != 0

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

	chunk := get_chunk_at(world, chunk_pos)
	if chunk == nil do return 0

	local_x := i32(math.floor((world_pos.x - chunk_x) / constants.BLOCK_SIZE))
	local_y := i32(math.floor((world_pos.y - chunk_y) / constants.BLOCK_SIZE))
	local_z := i32(math.floor((world_pos.z - chunk_z) / constants.BLOCK_SIZE))

	return chunk_get_block_local(chunk, local_x, local_y, local_z)
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
				if block != 0 {
					return true
				}
			}
		}
	}

	return false
}