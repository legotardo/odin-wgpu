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

chunk_generate_task :: proc(t: thread.Task) {
	free_all(context.temp_allocator)

	data := cast(^ChunkGenTaskData)t.data

	if data.world.entities[data.entity_index] != data.entity do return

	chunk := &data.world.chunks[data.entity_index]

	if len(chunk.palette) == 0 {
		append(&chunk.palette, ecs.Block.Air)
	}

	seed: i32 = 12345

	chunk_size := constants.CHUNK_SIZE
	block_size := constants.BLOCK_SIZE
	chunk_base_x := f32(math.round(data.chunk_pos.x / block_size))
	chunk_base_y := i32(math.round(data.chunk_pos.y / block_size))
	chunk_base_z := f32(math.round(data.chunk_pos.z / block_size))

	terrain_buffer := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)
	temp_buffer    := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)
	humid_buffer   := make([]f32, constants.CHUNK_SIZE_SQUARED, context.temp_allocator)

	fast_noise.GenUniformGrid2D(data.terrain_node, raw_data(terrain_buffer), chunk_base_x, chunk_base_z, chunk_size, chunk_size, 1, 1, seed, nil)
	fast_noise.GenUniformGrid2D(data.temp_node, raw_data(temp_buffer), chunk_base_x, chunk_base_z, chunk_size, chunk_size, 1, 1, seed + 1, nil)
	fast_noise.GenUniformGrid2D(data.humid_node, raw_data(humid_buffer), chunk_base_x, chunk_base_z, chunk_size, chunk_size, 1, 1, seed + 2, nil)

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

			global_x := i32(chunk_base_x) + x
			global_z := i32(chunk_base_z) + z

			for y in 0 ..< chunk_size {
				world_block_y := chunk_base_y + y

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

	// for z in 0 ..< chunk_size {
	// 	for x in 0 ..< chunk_size {
	// 		idx := z * chunk_size + x

	// 		temp_idx := biome_noise_to_index_threshold(temp_buffer[idx])
	// 		humid_idx := biome_noise_to_index_threshold(humid_buffer[idx])
	// 		biome_id := biome_matrix[humid_idx][temp_idx]
	// 		config := biome_catalog[biome_id]

	// 		if len(config.props) == 0 do continue

	// 		global_x := i32(chunk_base_x) + x
	// 		global_z := i32(chunk_base_z) + z

	// 		spawn_roll := biome_spatial_hash_f32(global_x, global_z, seed + 999)

	// 		for prop in config.props {
	// 			if spawn_roll < prop.rarity {
	// 				if prop.prefab == nil do break

	// 				can_spawn := true
	// 				if prop.min_spacing > 0 {
	// 					spacing_loop: for sz in -prop.min_spacing ..= prop.min_spacing {
	// 						for sx in -prop.min_spacing ..= prop.min_spacing {
	// 							if sx == 0 && sz == 0 do continue

	// 							nx := global_x + sx
	// 							nz := global_z + sz
								
	// 							n_roll := biome_spatial_hash_f32(nx, nz, seed + 999)

	// 							if n_roll < prop.rarity && n_roll < spawn_roll {
	// 								can_spawn = false
	// 								break spacing_loop
	// 							}
	// 						}
	// 					}
	// 				}

	// 				if !can_spawn do break

	// 				terrain_height_raw := terrain_buffer[idx]
	// 				surface_block_y := i32(BASE_HEIGHT + (terrain_height_raw * HEIGHT_AMPLITUDE))

	// 				world_x := chunk_base_x + f32(x)
	// 				world_y := f32(surface_block_y + 1)
	// 				world_z := chunk_base_z + f32(z)

	// 				tree_world_x := world_x - f32(prop.prefab.width / 2)
	// 				tree_world_z := world_z - f32(prop.prefab.depth / 2)

	// 				stamped := stamp_prefab(
	// 					chunk,
	// 					prop.prefab,
	// 					{tree_world_x, world_y, tree_world_z},
	// 					{chunk_base_x, f32(chunk_base_y), chunk_base_z},
	// 				)

	// 				blocks_stamped += stamped
	// 				break
	// 			}
	// 		}
	// 	}
	// }

	max_blocks := chunk_size * chunk_size * chunk_size
	if blocks_placed == 0 {
		chunk.is_empty = true
	} else if blocks_placed == max_blocks {
		chunk.is_all_solid = true
	}
}
