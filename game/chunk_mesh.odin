package game

import "core:thread"
import "../ecs"
import "../renderer"
import "../constants"

chunk_mesh_task :: proc(t: thread.Task) {
	free_all(context.temp_allocator)

	data := cast(^ChunkTaskData)t.data

	entity_index := ecs.entity_index(data.entity)

	temp_vertices, temp_indices := generate_chunk_mesh(
		data.world,
		entity_index,
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
	chunk_idx: u32,
	chunk_pos: [3]i32,
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
					
					block_current := world_get_chunk_block(world, chunk_idx, voxel_pos[0], voxel_pos[1], voxel_pos[2], neighbor_indices, neighbor_entities)
					block_neighbor := world_get_chunk_block(world, chunk_idx, voxel_pos[0] + neighbor_dir[0], voxel_pos[1] + neighbor_dir[1], voxel_pos[2] + neighbor_dir[2], neighbor_indices, neighbor_entities)

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

						bottom_left := renderer.Vertex{
							position = {
								f32(quad_pos[0] + chunk_pos.x), 
								f32(quad_pos[1] + chunk_pos.y), 
								f32(quad_pos[2] + chunk_pos.z)
							},
							material_id = mat_id, normal_id = normal_id, ao = current_mask.ao[0],
						}
						bottom_right := renderer.Vertex{
							position = {
								f32(quad_pos[0] + delta_u[0] + chunk_pos.x), 
								f32(quad_pos[1] + delta_u[1] + chunk_pos.y), 
								f32(quad_pos[2] + delta_u[2] + chunk_pos.z)
							},
							material_id = mat_id, normal_id = normal_id, ao = current_mask.ao[1],
						}
						top_right := renderer.Vertex{
							position = {
								f32(quad_pos[0] + delta_u[0] + delta_v[0] + chunk_pos.x), 
								f32(quad_pos[1] + delta_u[1] + delta_v[1] + chunk_pos.y), 
								f32(quad_pos[2] + delta_u[2] + delta_v[2] + chunk_pos.z)
							},
							material_id = mat_id, normal_id = normal_id, ao = current_mask.ao[2],
						}
						top_left := renderer.Vertex{
							position = {
								f32(quad_pos[0] + delta_v[0] + chunk_pos.x), 
								f32(quad_pos[1] + delta_v[1] + chunk_pos.y), 
								f32(quad_pos[2] + delta_v[2] + chunk_pos.z)
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
	chunk_idx: u32,
	check_pos: [3]i32,
	u_dir, v_dir: [3]i32,
	neighbor_indices: [6]int,
	neighbor_entities: [6]ecs.Entity,
) -> (ao_bl, ao_br, ao_tr, ao_tl: f32) {
	side_l := world_get_chunk_block(world, chunk_idx, check_pos[0] - u_dir[0], check_pos[1] - u_dir[1], check_pos[2] - u_dir[2], neighbor_indices, neighbor_entities) != .Air
	side_r := world_get_chunk_block(world, chunk_idx, check_pos[0] + u_dir[0], check_pos[1] + u_dir[1], check_pos[2] + u_dir[2], neighbor_indices, neighbor_entities) != .Air
	side_b := world_get_chunk_block(world, chunk_idx, check_pos[0] - v_dir[0], check_pos[1] - v_dir[1], check_pos[2] - v_dir[2], neighbor_indices, neighbor_entities) != .Air
	side_t := world_get_chunk_block(world, chunk_idx, check_pos[0] + v_dir[0], check_pos[1] + v_dir[1], check_pos[2] + v_dir[2], neighbor_indices, neighbor_entities) != .Air

	corner_bl := world_get_chunk_block(world, chunk_idx, check_pos[0] - u_dir[0] - v_dir[0], check_pos[1] - u_dir[1] - v_dir[1], check_pos[2] - u_dir[2] - v_dir[2], neighbor_indices, neighbor_entities) != .Air
	corner_br := world_get_chunk_block(world, chunk_idx, check_pos[0] + u_dir[0] - v_dir[0], check_pos[1] + u_dir[1] - v_dir[1], check_pos[2] + u_dir[2] - v_dir[2], neighbor_indices, neighbor_entities) != .Air
	corner_tr := world_get_chunk_block(world, chunk_idx, check_pos[0] + u_dir[0] + v_dir[0], check_pos[1] + u_dir[1] + v_dir[1], check_pos[2] + u_dir[2] + v_dir[2], neighbor_indices, neighbor_entities) != .Air
	corner_tl := world_get_chunk_block(world, chunk_idx, check_pos[0] - u_dir[0] + v_dir[0], check_pos[1] - u_dir[1] + v_dir[1], check_pos[2] - u_dir[2] + v_dir[2], neighbor_indices, neighbor_entities) != .Air

	ao_bl = vertex_ao(side_l, side_b, corner_bl)
	ao_br = vertex_ao(side_r, side_b, corner_br)
	ao_tr = vertex_ao(side_r, side_t, corner_tr)
	ao_tl = vertex_ao(side_l, side_t, corner_tl)

	return
}
