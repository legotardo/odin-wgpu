package game

import "core:sync"
import "core:thread"
import "../constants"
import "../ecs"
import "../libs/fast_noise"

terrain_node := fast_noise.NewFromEncodedNodeTree("DQAH@BC@AIEAJBw@ABZEED0KV78YZmZmPwQDmpkZPwsAAIA/BA==", transmute(u32)~u32(0))
temp_node := fast_noise.NewFromEncodedNodeTree("DQAE@BCKRwvT8JBgAAKIVECAY@BQ16NwvxjhetQ/BAO4HoW+C4/CdT0E", transmute(u32)~u32(0))
humid_node := fast_noise.NewFromEncodedNodeTree("DQAE@BCKRwvT8JC@BHpECAY@BQFK5HvxjhetQ/BAO4HoW+C4/CdT0E", transmute(u32)~u32(0))

chunk_generate_terrain :: proc(t: thread.Task) {
	free_all(context.temp_allocator)

	data := cast(^ChunkGenTaskData)t.data
	entity_index := ecs.entity_index(data.entity)

	chunk := &data.world.chunks[entity_index]

	if len(chunk.palette) == 0 {
		append(&chunk.palette, ecs.Block.Air)
	}

	seed: i32 = 12345

	chunk_size := constants.CHUNK_SIZE
	chunk_start_x := data.chunk_pos.x
	chunk_start_y := data.chunk_pos.y
	chunk_start_z := data.chunk_pos.z

	terrain_buffer := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)
	temp_buffer    := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)
	humid_buffer   := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)

	fast_noise.GenUniformGrid2D(data.terrain_node, raw_data(terrain_buffer), f32(chunk_start_x), f32(chunk_start_z), chunk_size, chunk_size, 1, 1, seed, nil)
	fast_noise.GenUniformGrid2D(data.temp_node, raw_data(temp_buffer), f32(chunk_start_x), f32(chunk_start_z), chunk_size, chunk_size, 1, 1, seed, nil)
	fast_noise.GenUniformGrid2D(data.humid_node, raw_data(humid_buffer), f32(chunk_start_x), f32(chunk_start_z), chunk_size, chunk_size, 1, 1, seed, nil)

	BASE_HEIGHT: f32 = 40.0
	HEIGHT_AMPLITUDE: f32 = 48.0
	blocks_placed: i32 = 0

	for z in 0 ..< chunk_size {
		for x in 0 ..< chunk_size {
			idx := z * chunk_size + x

			terrain_height_raw := terrain_buffer[z * chunk_size + x]
			surface_block_y := i32(BASE_HEIGHT + (terrain_height_raw * HEIGHT_AMPLITUDE))

			temp_idx := biome_noise_to_index_threshold(temp_buffer[idx])
			humid_idx := biome_noise_to_index_threshold(humid_buffer[idx])
			
			biome_id := biome_matrix[humid_idx][temp_idx]
			config := biome_catalog[biome_id]

			global_x := i32(chunk_start_x) + x
			global_z := i32(chunk_start_z) + z

			for y in 0 ..< chunk_size {
				world_block_y := chunk_start_y + y

				if world_block_y <= surface_block_y {
					block_to_place: ecs.Block = .Air

					if world_block_y == surface_block_y {
						block_to_place = biome_get_variant_block(config.surface_blocks, global_x, world_block_y, global_z)
					} else if world_block_y > surface_block_y - config.sub_surface_depth {
						block_to_place = config.sub_surface_block
					} else {
						block_to_place = config.base_block
					}

					chunk_set_block(chunk, x, y, z, block_to_place)
					blocks_placed += 1
				}
			}
		}
	}

	max_blocks := chunk_size * chunk_size * chunk_size
	if blocks_placed == 0 {
		chunk.is_empty = true
	} else if blocks_placed == max_blocks {
		chunk.is_all_solid = true
	}
}

chunk_generate_decoration :: proc(t: thread.Task) {
	free_all(context.temp_allocator)

	data := cast(^ChunkGenDecorationData)t.data
	entity_index := ecs.entity_index(data.entity)

	chunk := &data.world.chunks[entity_index]

	seed: i32 = 12345

	chunk_size := constants.CHUNK_SIZE
	chunk_start_x := data.chunk_pos.x
	chunk_start_y := data.chunk_pos.y
	chunk_start_z := data.chunk_pos.z

	terrain_buffer := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)
	temp_buffer    := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)
	humid_buffer   := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)

	fast_noise.GenUniformGrid2D(data.terrain_node, raw_data(terrain_buffer), f32(chunk_start_x), f32(chunk_start_z), chunk_size, chunk_size, 1, 1, seed, nil)
	fast_noise.GenUniformGrid2D(data.temp_node, raw_data(temp_buffer), f32(chunk_start_x), f32(chunk_start_z), chunk_size, chunk_size, 1, 1, seed, nil)
	fast_noise.GenUniformGrid2D(data.humid_node, raw_data(humid_buffer), f32(chunk_start_x), f32(chunk_start_z), chunk_size, chunk_size, 1, 1, seed, nil)

	BASE_HEIGHT: f32 = 40.0
	HEIGHT_AMPLITUDE: f32 = 48.0

	blocks_placed := 0

	for z in 0 ..< chunk_size {
		for x in 0 ..< chunk_size {
			idx := z * chunk_size + x

			temp_idx := biome_noise_to_index_threshold(temp_buffer[idx])
			humid_idx := biome_noise_to_index_threshold(humid_buffer[idx])
			
			biome_id := biome_matrix[humid_idx][temp_idx]
			config := biome_catalog[biome_id]

			if len(config.props) == 0 do continue

			global_x := i32(chunk_start_x) + x
			global_z := i32(chunk_start_z) + z

			spawn_roll := biome_spatial_hash_f32(global_x, global_z, seed)

			terrain_height_raw := terrain_buffer[idx]
			local_surface_y := i32(BASE_HEIGHT + (terrain_height_raw * HEIGHT_AMPLITUDE))

			for prop in config.props {
				if spawn_roll < prop.rarity {
					if prop.prefab == nil do break

					if chunk_get_block_local(chunk, x, local_surface_y - data.chunk_pos.y, z) == .Air do break

					blocks_placed += world_stamp_prefab(
						data.world,
						chunk,
						data.chunk_pos, 
						{ x, local_surface_y + 1 - data.chunk_pos.y, z },
						prop.prefab,
					)

					break
				}
			}
		}
	}

	if chunk.is_empty && blocks_placed > 0 {
		chunk.is_empty = false
	}
}

chunk_generate_missing_blocks :: proc(t: thread.Task) {
	free_all(context.temp_allocator)

	data := cast(^ChunkGenMissingBlocksData)t.data
	entity_index := ecs.entity_index(data.entity)

	chunk := &data.world.chunks[entity_index]

	apply_missing_blocks(data.world, chunk, data.chunk_pos)
}

@(private)
apply_missing_blocks :: proc(world: ^ecs.World, chunk: ^ecs.ChunkComponent, key: ecs.ChunkPos) -> int {
	blocks_placed := 0

	sync.mutex_lock(&world.chunk_missing_blocks_mu)
	if list, ok := &world.chunk_missing_blocks[key]; ok {
		for missing_block in list {
			target_palette_idx := chunk_get_or_add_palette_idx(chunk, missing_block.block)
			chunk_set_block_fast(chunk, missing_block.x, missing_block.y, missing_block.z, target_palette_idx)
			blocks_placed += 1
		}
		delete(list^)
		delete_key(&world.chunk_missing_blocks, key)
	}
	sync.mutex_unlock(&world.chunk_missing_blocks_mu)

	if blocks_placed > 0 {
		chunk.is_empty = false
	}

	return blocks_placed
}
