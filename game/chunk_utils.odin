package game

import "core:slice"
import "core:math"
import "core:math/linalg"
import "../constants"
import "../ecs"

CHUNK_LOD_2_DIST :: 64 * 64
CHUNK_LOD_4_DIST :: 128 * 128
CHUNK_LOD_8_DIST :: 256 * 256

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
world_get_block_at :: proc(world: ^ecs.World, world_pos: linalg.Vector3f32) -> ecs.Block {
	chunk_size_world := f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE

	chunk_x := math.floor(world_pos.x / chunk_size_world) * chunk_size_world
	chunk_y := math.floor(world_pos.y / chunk_size_world) * chunk_size_world
	chunk_z := math.floor(world_pos.z / chunk_size_world) * chunk_size_world

	chunk_pos := linalg.Vector3f32{chunk_x, chunk_y, chunk_z}

	chunk_idx := world_get_chunk_at(world, chunk_pos)
	if chunk_idx == -1 do return .Air

	local_x := i32(math.floor((world_pos.x - chunk_x) / constants.BLOCK_SIZE))
	local_y := i32(math.floor((world_pos.y - chunk_y) / constants.BLOCK_SIZE))
	local_z := i32(math.floor((world_pos.z - chunk_z) / constants.BLOCK_SIZE))

	return chunk_get_block_local(&world.chunks[chunk_idx], local_x, local_y, local_z)
}

@(private)
world_get_chunk_at :: proc(world: ^ecs.World, pos: linalg.Vector3f32) -> int {
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

				block := world_get_block_at(world, world_pos)
				if block != .Air {
					return true
				}
			}
		}
	}

	return false
}

@(private)
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
		idx := world_get_chunk_index(x, y, z)
		blocks_per_u64 := 64 / i32(chunk.bits_per_block)
		data_idx := idx / blocks_per_u64
		bit_offset := uint(idx % blocks_per_u64) * uint(chunk.bits_per_block)

		mask := (u64(1) << uint(chunk.bits_per_block)) - 1

		chunk.packed_blocks[data_idx] &= ~(mask << bit_offset)
		chunk.packed_blocks[data_idx] |= (u64(palette_idx) & mask) << bit_offset
	}
}

@(private)
world_build_spawn_offsets :: proc(world: ^ecs.World) {
	offsets := make([dynamic]ecs.ChunkOffset)

    expanded_render := world.render_distance + 1

	for y := -expanded_render; y <= expanded_render; y += 1 {
		for z := -expanded_render; z <= expanded_render; z += 1 {
			for x := -expanded_render; x <= expanded_render; x += 1 {
				d := f32(x*x + y*y + z*z)
				append(&offsets, ecs.ChunkOffset{x, y, z, d})
			}
		}
	}

	slice.sort_by(offsets[:], proc(a, b: ecs.ChunkOffset) -> bool {
		return a.dist_sq < b.dist_sq
	})

    world.chunk_spawn_offset = offsets
}
