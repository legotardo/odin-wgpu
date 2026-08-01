package game

import "core:math/linalg"
import "core:thread"
import "core:fmt"
import "../constants"
import "../ecs"
import "../renderer"

spawn_world_chunks :: proc(state: ^GameState) {
	for z in 0..< constants.WORLD_SIZE {
		for x in 0..< constants.WORLD_SIZE {
			chunk := ecs.entity_create(state.world)
			ecs.entity_add_transform(state.world, chunk, {
				position = { f32(x * constants.CHUNK_SIZE), 0, f32(z * constants.CHUNK_SIZE) },
				scale = { 1, 1, 1 }
			})
			ecs.entity_add_chunk(state.world, chunk, {})
		}
	}
}

system_generate_chunk :: proc(state: ^GameState) {
	mask := ecs.ComponentMask{.TransformComponent, .ChunkComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) != mask do continue

		chunk := &state.world.chunks[i]

		if chunk.is_generated do continue

		for z in 0 ..< constants.CHUNK_SIZE {
			for y in 0 ..< constants.CHUNK_SIZE {
				for x in 0 ..< constants.CHUNK_SIZE {
					if y == 0 {
						chunk_set_block(chunk, x, y, z, 1)
					} else if y < 3 && (x % 4 == 0 || z % 5 == 0) {
						chunk_set_block(chunk, x, y, z, 2)
					} else {
						chunk_set_block(chunk, x, y, z, 0)
					}
				}
			}
		}

		chunk.is_generated = true
		chunk.is_dirty = true
	}
}

system_generate_chunk_mesh :: proc(state: ^GameState) {
	mask := ecs.ComponentMask{.TransformComponent, .ChunkComponent}

	cam_t := game_get_camera_transform(state)
	cam_pos := cam_t.position

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) != mask do continue

		chunk := &state.world.chunks[i]
		t := &state.world.transforms[i]
		
		dist := linalg.distance(t.position, cam_pos)

		desired_lod := 1
		if dist > 256.0 {
			desired_lod = 8
		} else if dist > 128 {
			desired_lod = 4
		} else if dist > 64 {
			desired_lod = 2
		}

		if chunk.current_lod != desired_lod {
			chunk.current_lod = desired_lod
			chunk.is_dirty = true
		}

		if chunk.is_generated && chunk.is_dirty && !chunk.is_meshing {
			chunk.is_meshing = true

			task_data := new(ChunkTaskData)
			task_data.chunk = chunk
			task_data.chunk_pos = t.position
			task_data.entity_index = i
			task_data.lod = desired_lod

			cs := f32(constants.CHUNK_SIZE)
			task_data.neighbors[0] = get_chunk_at(state.world, t.position + {-cs, 0  , 0})
			task_data.neighbors[1] = get_chunk_at(state.world, t.position + {cs , 0  , 0})
			task_data.neighbors[2] = get_chunk_at(state.world, t.position + {0  , -cs, 0})
			task_data.neighbors[3] = get_chunk_at(state.world, t.position + {0  , cs , 0})
			task_data.neighbors[4] = get_chunk_at(state.world, t.position + {0  , 0  , -cs})
			task_data.neighbors[5] = get_chunk_at(state.world, t.position + {0  , 0  , cs})

			thread.pool_add_task(state.thread_pool, context.allocator, chunk_mesh_task, task_data, 0)
		}
	}

	for thread.pool_num_done(state.thread_pool) > 0 {
		task, ok := thread.pool_pop_done(state.thread_pool)
		if !ok do continue
		data := cast(^ChunkTaskData)task.data

		if len(data.vertices) > 0 {
			mesh := renderer.mesh_create(state.renderer, data.vertices, data.indices)
			mesh_handle := assets_register_mesh(&state.assets, fmt.aprintf("chunk_%f_%f_%f", data.chunk_pos.x, data.chunk_pos.y, data.chunk_pos.z), mesh)

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

chunk_mesh_task :: proc(t: thread.Task) {
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
	lod: int,
) -> ([]renderer.Vertex, []u16) {
	vertices := make([dynamic]renderer.Vertex, context.temp_allocator)
	indices := make([dynamic]u16, context.temp_allocator)

	cs_lod := (constants.CHUNK_SIZE + lod - 1) / lod
	mask := make([]i16, cs_lod * cs_lod, context.temp_allocator)

	// Search by 3 dimesions
	for axis in 0..<3 {
		axis_u := (axis + 1) % 3
		axis_v := (axis + 2) % 3

		voxel_pos := [3]int{0, 0, 0}
		neighbor_dir := [3]int{0, 0, 0}
		neighbor_dir[axis] = lod

		for voxel_pos[axis] = -lod; voxel_pos[axis] < constants.CHUNK_SIZE; voxel_pos[axis] += lod {
			mask_idx := 0

			// Create the mask
			for v_idx in 0..<cs_lod {
				voxel_pos[axis_v] = v_idx * lod
				for u_idx in 0..<cs_lod {
					voxel_pos[axis_u] = u_idx * lod
					block_current := chunk_get_block(chunk, voxel_pos[0], voxel_pos[1], voxel_pos[2], neighbors)
					block_neighbor := chunk_get_block(chunk, voxel_pos[0] + neighbor_dir[0], voxel_pos[1] + neighbor_dir[1], voxel_pos[2] + neighbor_dir[2], neighbors)

					if block_current != 0 && block_neighbor == 0 {
						mask[mask_idx] = i16(block_current)
					} else if block_current == 0 && block_neighbor != 0 {
						mask[mask_idx] = -i16(block_neighbor)
					} else {
						mask[mask_idx] = 0
					}

					mask_idx += 1
				}
			}

			mask_idx = 0
			for row := 0; row < cs_lod; row += 1 {
				for col := 0; col < cs_lod; {
					if mask[mask_idx] != 0 {
						current_mask := mask[mask_idx]

						quad_width := 1
						for col + quad_width < cs_lod && mask[mask_idx + quad_width] == current_mask {
							quad_width += 1
						}

						quad_height := 1

						outer: for row + quad_height < cs_lod {
							for check_col := 0; check_col < quad_width; check_col += 1 {
								if mask[mask_idx + check_col + quad_height * cs_lod] != current_mask {
									break outer
								}
							}

							quad_height += 1
						}

						delta_u := [3]int{0, 0, 0}
						delta_v := [3]int{0, 0, 0}
						delta_u[axis_u] = quad_width * lod
						delta_v[axis_v] = quad_height * lod

						quad_pos := [3]int{0, 0, 0}
						quad_pos[axis] = voxel_pos[axis]
						quad_pos[axis_u] = col * lod
						quad_pos[axis_v] = row * lod
						quad_pos[axis] += lod

						mat_id := u8(abs(current_mask))

						normal_id := u8(axis * 2)
						if current_mask < 0 {
							normal_id += 1
						}

						bottom_left := renderer.Vertex{
							position = {
								f32(quad_pos[0]) + chunk_pos.x,
								f32(quad_pos[1]) + chunk_pos.y,
								f32(quad_pos[2]) + chunk_pos.z,
							},
							material_id = mat_id,
							normal_id = normal_id,
						}
						bottom_right := renderer.Vertex{
							position = {
								f32(quad_pos[0] + delta_u[0]) + chunk_pos.x,
								f32(quad_pos[1] + delta_u[1]) + chunk_pos.y,
								f32(quad_pos[2] + delta_u[2]) + chunk_pos.z,
							},
							material_id = mat_id,
							normal_id = normal_id,
						}

						top_right := renderer.Vertex{
							position = {
								f32(quad_pos[0] + delta_u[0] + delta_v[0]) + chunk_pos.x,
								f32(quad_pos[1] + delta_u[1] + delta_v[1]) + chunk_pos.y,
								f32(quad_pos[2] + delta_u[2] + delta_v[2]) + chunk_pos.z,
							},
							material_id = mat_id,
							normal_id = normal_id,
						}
						top_left := renderer.Vertex{
							position = {
								f32(quad_pos[0] + delta_v[0]) + chunk_pos.x,
								f32(quad_pos[1] + delta_v[1]) + chunk_pos.y,
								f32(quad_pos[2] + delta_v[2]) + chunk_pos.z,
							},
							material_id = mat_id,
							normal_id = normal_id,
						}

						append(&vertices, bottom_left, bottom_right, top_right, top_left)
						idx := u16(len(vertices) - 4)

						if current_mask > 0 {
							append(&indices, idx, idx + 1, idx + 2)
							append(&indices, idx, idx + 2, idx + 3)
						} else {
							append(&indices, idx, idx + 2, idx + 1)
							append(&indices, idx, idx + 3, idx + 2)
						}

						for clear_y := 0; clear_y < quad_height; clear_y += 1 {
							for clear_x := 0; clear_x < quad_width; clear_x += 1 {
								mask[mask_idx + clear_x + clear_y * cs_lod] = 0
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
chunk_get_index :: proc(x, y, z: int) -> int {
	return x + (y * constants.CHUNK_SIZE) + (z * constants.CHUNK_SIZE * constants.CHUNK_SIZE)
}

@(private = "file")
chunk_get_block :: proc(chunk: ^ecs.ChunkComponent, x, y, z: int, neighbors: [6]^ecs.ChunkComponent) -> ecs.Block {
	if x < 0 {
		if neighbors[0] == nil do return 0
		return chunk_get_block_local(neighbors[0], constants.CHUNK_SIZE + x, y, z)
	} else if x >= constants.CHUNK_SIZE {
		if neighbors[1] == nil do return 0
		return chunk_get_block_local(neighbors[1], x - constants.CHUNK_SIZE, y, z)
	} else if y < 0 {
		if neighbors[2] == nil do return 0
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

chunk_get_block_local :: proc(chunk: ^ecs.ChunkComponent, x, y, z: int) -> ecs.Block {
	if x < 0 ||
	   x >= constants.CHUNK_SIZE ||
	   y < 0 ||
	   y >= constants.CHUNK_SIZE ||
	   z < 0 ||
	   z >= constants.CHUNK_SIZE {
		return 0
	}

	if chunk.bits_per_block == 0 {
		return chunk.palette[0]
	}

	idx := chunk_get_index(x, y, z)

	blocks_per_u64 := 64 / int(chunk.bits_per_block)
	data_idx := idx / blocks_per_u64
	bit_offset := uint(idx % blocks_per_u64) * uint(chunk.bits_per_block)

	mask := (u64(1) << uint(chunk.bits_per_block)) - 1
	palette_idx := (chunk.packed_blocks[data_idx] >> bit_offset) & mask

	return chunk.palette[palette_idx]
}

@(private = "file")
chunk_set_block :: proc(chunk: ^ecs.ChunkComponent, x, y, z: int, block: ecs.Block) {
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
		blocks_per_u64 := 64 / int(chunk.bits_per_block)
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
		blocks_per_u64 := 64 / int(new_bits)
		total_blocks := constants.CHUNK_SIZE_CUBED
		data_len := (total_blocks + blocks_per_u64 - 1) / blocks_per_u64

		chunk.packed_blocks = make([]u64, data_len)

		if len(old_data) > 0 {
			old_blocks_per_u64 := 64 / int(old_bits)
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