package game

import "core:fmt"
import "../constants"
import "../ecs"
import "../renderer"

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

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) != mask do continue

		chunk := &state.world.chunks[i]
		t := &state.world.transforms[i]

		if !chunk.is_generated || !chunk.is_dirty do continue

		vertices, indices := generate_chunk_mesh(chunk, t)

		if len(vertices) > 0 {
			mesh := renderer.mesh_create(state.renderer, vertices, indices)
			mesh_handle := assets_register_mesh(&state.assets, fmt.aprintf("chunk_%f_%f_%f", t.position.x, t.position.y, t.position.z), mesh)

			ecs.entity_add_render(state.world, state.world.entities[i], {
				mesh = string(mesh_handle),
				material = "chunk",
				ignore_instancing = true,
			})
		}

		chunk.is_dirty = false
	}
}

@(private = "file")
generate_chunk_mesh :: proc(chunk: ^ecs.ChunkComponent, transform: ^ecs.TransformComponent) -> ([]renderer.Vertex, []u16) {
	vertices := make([dynamic]renderer.Vertex, context.temp_allocator)
	indices := make([dynamic]u16, context.temp_allocator)

	mask := make([]i16, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)

	// Search by 3 dimesions
	for axis in 0..<3 {
		axis_u := (axis + 1) % 3
		axis_v := (axis + 2) % 3

		voxel_pos := [3]int{0, 0, 0}
		neighbor_dir := [3]int{0, 0, 0}
		neighbor_dir[axis] = 1

		for voxel_pos[axis] = -1; voxel_pos[axis] < constants.CHUNK_SIZE; voxel_pos[axis] += 1 {
			mask_idx := 0

			// Create the mask
			for voxel_pos[axis_v] = 0; voxel_pos[axis_v] < constants.CHUNK_SIZE; voxel_pos[axis_v] += 1 {
				for voxel_pos[axis_u] = 0; voxel_pos[axis_u] < constants.CHUNK_SIZE; voxel_pos[axis_u] += 1 {
					block_current := chunk_get_block(chunk, voxel_pos[0], voxel_pos[1], voxel_pos[2])
					block_neighbor := chunk_get_block(chunk, voxel_pos[0] + neighbor_dir[0], voxel_pos[1] + neighbor_dir[1], voxel_pos[2] + neighbor_dir[2])

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
			for row := 0; row < constants.CHUNK_SIZE; row += 1 {
				for col := 0; col < constants.CHUNK_SIZE; {
					if mask[mask_idx] != 0 {
						current_mask := mask[mask_idx]

						quad_width := 1
						for col + quad_width < constants.CHUNK_SIZE && mask[mask_idx + quad_width] == current_mask {
							quad_width += 1
						}

						quad_height := 1

						outer: for row + quad_height < constants.CHUNK_SIZE {
							for check_col := 0; check_col < quad_width; check_col += 1 {
								if mask[mask_idx + check_col + quad_height * constants.CHUNK_SIZE] != current_mask {
									break outer
								}
							}

							quad_height += 1
						}

						delta_u := [3]int{0, 0, 0}
						delta_v := [3]int{0, 0, 0}
						delta_u[axis_u] = quad_width
						delta_v[axis_v] = quad_height

						quad_pos := [3]int{0, 0, 0}
						quad_pos[axis] = voxel_pos[axis]
						quad_pos[axis_u] = col
						quad_pos[axis_v] = row
						quad_pos[axis] += 1

						mat_id := u8(abs(current_mask))

						normal_id := u8(axis * 2)
						if current_mask < 0 {
							normal_id += 1
						}

						chunk_pos := transform.position

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
								mask[mask_idx + clear_x + clear_y * constants.CHUNK_SIZE] = 0
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
chunk_get_block :: proc(chunk: ^ecs.ChunkComponent, x, y, z: int) -> ecs.Block {
	if x < 0 ||
	   x >= constants.CHUNK_SIZE ||
	   y < 0 ||
	   y >= constants.CHUNK_SIZE ||
	   z < 0 ||
	   z >= constants.CHUNK_SIZE {
		return 0
	}

	idx := chunk_get_index(x, y, z)
	return chunk.blocks[idx]
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

	idx := chunk_get_index(x, y, z)
	chunk.blocks[idx] = block
}
