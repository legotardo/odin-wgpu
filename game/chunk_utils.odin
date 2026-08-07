package game

import "core:slice"
import "core:math"
import "core:math/linalg"
import "../constants"
import "../ecs"
import "../renderer"

CHUNK_LOD_2_DIST :: 256 * 256
CHUNK_LOD_4_DIST :: 512 * 512
CHUNK_LOD_8_DIST :: 1024 * 1024

@(private)
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

	idx := world_get_chunk_index(x, y, z)

	blocks_per_u64 := 64 / i32(chunk.bits_per_block)
	data_idx := idx / blocks_per_u64
	bit_offset := uint(idx % blocks_per_u64) * uint(chunk.bits_per_block)

	mask := (u64(1) << uint(chunk.bits_per_block)) - 1
	palette_idx := (chunk.packed_blocks[data_idx] >> bit_offset) & mask

	return chunk.palette[palette_idx]
}

@(private)
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

	chunk_set_block_fast(chunk, x, y, z, palette_idx)
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

@(private)
world_get_chunk_block :: proc(world: ^ecs.World, chunk_idx: u32, x, y, z: i32, neighbor_indices: [6]int, neighbor_entities: [6]ecs.Entity) -> ecs.Block {
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

@(private)
world_get_relative_block_at :: proc(world: ^ecs.World, world_pos: linalg.Vector3f32) -> ecs.Block {
	bs := constants.BLOCK_SIZE

	block_x := i32(math.floor(world_pos.x / bs))
	block_y := i32(math.floor(world_pos.y / bs))
	block_z := i32(math.floor(world_pos.z / bs))

	cx := i32(math.floor(f32(block_x) / f32(constants.CHUNK_SIZE)))
	cy := i32(math.floor(f32(block_y) / f32(constants.CHUNK_SIZE)))
	cz := i32(math.floor(f32(block_z) / f32(constants.CHUNK_SIZE)))

	chunk_idx := world_get_chunk_at(world, {cx, cy, cz})
	if chunk_idx == -1 do return .Air

	local_x := block_x - (cx * constants.CHUNK_SIZE)
	local_y := block_y - (cy * constants.CHUNK_SIZE)
	local_z := block_z - (cz * constants.CHUNK_SIZE)

	return chunk_get_block_local(&world.chunks[chunk_idx], local_x, local_y, local_z)
}

@(private)
world_get_chunk_at :: proc(world: ^ecs.World, chunk_coord: [3]i32) -> int {
	if idx, ok := world.chunk_map[chunk_coord]; ok {
		return idx
	}
	
	return -1
}

@(private)
world_get_chunk_index :: proc(x, y, z: i32) -> i32 {
	return x + (y * constants.CHUNK_SIZE) + (z * constants.CHUNK_SIZE * constants.CHUNK_SIZE)
}

@(private)
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

				block := world_get_relative_block_at(world, world_pos)
				if block != .Air {
					return true
				}
			}
		}
	}

	return false
}

@(private)
world_stamp_prefab :: proc(
	world: ^ecs.World,
	chunk: ^ecs.ChunkComponent,
	chunk_global_pos: [3]i32,
	chunk_local_position: [3]i32,
	prefab: ^VoxelPrefab,
) -> i32 {
	blocks_stamped: i32 = 0

	offset_x := -i32(prefab.width / 2)
	// offset_y := -i32(prefab.height / 2)
	offset_z := -i32(prefab.depth / 2)

	// b_idx := chunk_get_or_add_palette_idx(chunk, .Blue)
	// chunk_set_block_fast(chunk, chunk_local_position[0] + 0, chunk_local_position[1] + 0, chunk_local_position[2] + 0, b_idx)
	// chunk_set_block_fast(chunk, chunk_local_position[0], chunk_local_position[1] - 1, chunk_local_position[2], b_idx)

	for py in 0 ..< prefab.height {
		for pz in 0 ..< prefab.depth {
			for px in 0 ..< prefab.width {
				idx := px + (py * prefab.width) + (pz * prefab.width * prefab.height)
				vox_color_index := prefab.blocks[idx]

				if vox_color_index == 0 do continue

				real_block := prefab.palette[vox_color_index]
				target_palette_idx := chunk_get_or_add_palette_idx(chunk, real_block)

				cx := chunk_local_position[0] + px + offset_x
				cy := chunk_local_position[1] + py
				cz := chunk_local_position[2] + pz + offset_z

				if cx < 0 || cx >= constants.CHUNK_SIZE ||
                   cy < 0 || cy >= constants.CHUNK_SIZE ||
                   cz < 0 || cz >= constants.CHUNK_SIZE {
                    continue
                }

				chunk_set_block_fast(chunk, cx, cy, cz, target_palette_idx)
				blocks_stamped += 1
			}
		}
	}

	return blocks_stamped;
}


@(private)
world_build_spawn_offsets :: proc(world: ^ecs.World) {
	offsets := make([dynamic]ecs.ChunkOffset)

    expanded_render := world.render_distance + 1

	for y := -expanded_render; y <= expanded_render; y += 1 {
		for z := -expanded_render; z <= expanded_render; z += 1 {
			for x := -expanded_render; x <= expanded_render; x += 1 {
				d := x*x + y*y + z*z
				append(&offsets, ecs.ChunkOffset{x, y, z, d})
			}
		}
	}

	slice.sort_by(offsets[:], proc(a, b: ecs.ChunkOffset) -> bool {
		return a.dist_sq < b.dist_sq
	})

    world.chunk_spawn_offset = offsets
}

@(private)
game_change_render_distance :: proc(state: ^GameState, render_distance: i32) {
	state.world.render_distance = render_distance

	renderer.renderer_update_render_config_buffer(state.renderer, {
		render_distance = render_distance,
	})

	world_build_spawn_offsets(state.world)
}

@(private)
chunk_get_or_add_palette_idx :: proc(chunk: ^ecs.ChunkComponent, block: ecs.Block) -> int {
	for p, i in chunk.palette {
		if p == block do return i
	}
	
	append(&chunk.palette, block)
	chunk_repack(chunk)
	
	return len(chunk.palette) - 1
}

@(private)
chunk_set_block_fast :: proc(chunk: ^ecs.ChunkComponent, x, y, z: i32, palette_idx: int) {
	if chunk.bits_per_block > 0 {
		idx := world_get_chunk_index(x, y, z)
		blocks_per_u64 := 64 / i32(chunk.bits_per_block)
		data_idx := idx / blocks_per_u64
		bit_offset := uint(idx % blocks_per_u64) * uint(chunk.bits_per_block)

		mask := (u64(1) << uint(chunk.bits_per_block)) - 1

		chunk.packed_blocks[data_idx] &= ~(mask << bit_offset)
		chunk.packed_blocks[data_idx] |= (u64(palette_idx) & mask) << bit_offset
	}
}
