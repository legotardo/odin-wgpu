package game

import "core:math"
import "core:math/linalg"
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
	block_size := constants.BLOCK_SIZE
	chunk_start_x := f32(math.round(data.chunk_pos.x / block_size))
	chunk_start_y := i32(math.round(data.chunk_pos.y / block_size))
	chunk_start_z := f32(math.round(data.chunk_pos.z / block_size))

	terrain_buffer := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)
	temp_buffer    := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)
	humid_buffer   := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)

	fast_noise.GenUniformGrid2D(data.terrain_node, raw_data(terrain_buffer), chunk_start_x, chunk_start_z, chunk_size, chunk_size, 1, 1, seed, nil)
	fast_noise.GenUniformGrid2D(data.temp_node, raw_data(temp_buffer), chunk_start_x, chunk_start_z, chunk_size, chunk_size, 1, 1, seed, nil)
	fast_noise.GenUniformGrid2D(data.humid_node, raw_data(humid_buffer), chunk_start_x, chunk_start_z, chunk_size, chunk_size, 1, 1, seed, nil)

	BASE_HEIGHT: f32 = 40.0
	HEIGHT_AMPLITUDE: f32 = 48.0
	blocks_placed: i32 = 0
	// blocks_stamped: i32 = 0

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
	block_size := constants.BLOCK_SIZE
	chunk_start_x := f32(math.round(data.chunk_pos.x / block_size))
	chunk_start_y := f32(math.round(data.chunk_pos.y / block_size))
	chunk_start_z := f32(math.round(data.chunk_pos.z / block_size))

	terrain_buffer := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)
	temp_buffer    := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)
	humid_buffer   := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)

	fast_noise.GenUniformGrid2D(data.terrain_node, raw_data(terrain_buffer), chunk_start_x, chunk_start_z, chunk_size, chunk_size, 1, 1, seed, nil)
	fast_noise.GenUniformGrid2D(data.temp_node, raw_data(temp_buffer), chunk_start_x, chunk_start_z, chunk_size, chunk_size, 1, 1, seed, nil)
	fast_noise.GenUniformGrid2D(data.humid_node, raw_data(humid_buffer), chunk_start_x, chunk_start_z, chunk_size, chunk_size, 1, 1, seed, nil)

	BASE_HEIGHT: f32 = 40.0
	HEIGHT_AMPLITUDE: f32 = 48.0

	blocks_placed: i32 = 0
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
			surface_block_y := i32(BASE_HEIGHT + (terrain_height_raw * HEIGHT_AMPLITUDE))
			local_surface_y := surface_block_y - i32(chunk_start_y)

			if local_surface_y < 0 || local_surface_y >= chunk_size do continue

			for prop in config.props {
				if spawn_roll < prop.rarity {
					if prop.prefab == nil do break

					if chunk_get_block_local(chunk, x, local_surface_y, z) == .Air do break

					y := local_surface_y + 1

					blocks_placed += world_stamp_prefab(
						data.world,
						chunk,
						data.chunk_pos, 
						{ x, y, z },
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
