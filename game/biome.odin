package game

import "../ecs"

BiomeType :: enum u8 {
	Desert,
	Plains,
}

BlockVariant :: struct {
	block:  ecs.Block,
	weight: int,
}

BiomeProp :: struct {
	prefab: ^VoxelPrefab,
	rarity: f32, // 0.0 - 1.0
	min_spacing: i32,
}

BiomeConfig :: struct {
	id:                BiomeType,
	name:              string,
	surface_blocks:    []BlockVariant,
	sub_surface_block: ecs.Block,
	sub_surface_depth: i32,
	base_block:        ecs.Block,
	props: []BiomeProp,
}

BIOME_ZONES :: 3

biome_matrix: [BIOME_ZONES][BIOME_ZONES]BiomeType = {
//              ^ Humid      ^ Temp
	{.Plains, .Plains, .Desert},
	{.Plains, .Plains, .Desert},
	{.Plains, .Plains, .Plains},
}

biome_catalog: [len(BiomeType)]BiomeConfig

biome_catalog_init :: proc(state: ^GameState) {
    plains_surface := make([]BlockVariant, 3)
    plains_surface[0] = {block = .Grass1, weight = 93}
    plains_surface[1] = {block = .Grass2, weight = 5}
    plains_surface[2] = {block = .Grass3, weight = 2}
    plains_props := make([]BiomeProp, 1)
	plains_props[0] = {
		prefab = assets_get_voxel_prefab(&state.assets, "tree"),
		min_spacing = 40,
		rarity = 0.001,
	}

	
    biome_catalog[BiomeType.Plains] = BiomeConfig{
        id = .Plains,
        name = "Plains",
        surface_blocks = plains_surface,
        sub_surface_block = .Grass1,
        sub_surface_depth = 4,
        base_block = .Grass1,
		props = plains_props,
    }

    desert_surface := make([]BlockVariant, 1)
    desert_surface[0] = {block = .Sand1, weight = 100}
	desert_props := make([]BiomeProp, 1)
	desert_props[0] = {
		prefab = assets_get_voxel_prefab(&state.assets, "cactus"),
		min_spacing = 20,
		rarity = 0.0001,
	}

    biome_catalog[BiomeType.Desert] = BiomeConfig{
        id = .Desert,
        name = "Desert",
        surface_blocks = desert_surface,
        sub_surface_block = .Sand1,
        sub_surface_depth = 4,
        base_block = .Sand1,
		props = desert_props,
    }
}

// https://github.com/aappleby/smhasher/blob/master/src/MurmurHash3.cpp
biome_spatial_hash :: proc(x, y, z: i32) -> u32 {
	p1: u32 = 73856093
	p2: u32 = 19349663
	p3: u32 = 83492791

	h := (u32(x) * p1) ~ (u32(y) * p2) ~ (u32(z) * p3)

	h ~= (h >> 16)
	h *= 0x85ebca6b
	h ~= (h >> 13)
	h *= 0xc2b2ae35
	h ~= (h >> 16)

	return h
}
biome_spatial_hash_f32 :: proc(x, y, seed: i32) -> f32 {
    h := u32(seed)

    h = h ~ (u32(x) * 0x27d4eb2d)
    h = (h << 17) | (h >> 15)

    h = h ~ (u32(y) * 0x85ebca6b)
    h = (h << 15) | (h >> 17)

    h = h ~ (h >> 16)
    h *= 0x85ebca6b
    h = h ~ (h >> 13)
    h *= 0xc2b2ae35
    h = h ~ (h >> 16)

    return f32(h) / 4294967295.0
}

biome_get_variant_block :: proc(variants: []BlockVariant, world_x, world_y, world_z: i32) -> ecs.Block {
	if len(variants) == 0 do return .Air
	if len(variants) == 1 do return variants[0].block

	hash_val := biome_spatial_hash(world_x, world_y, world_z)
	
	rand_val := int(hash_val % 100)

	cumulative: int = 0
	for v in variants {
		cumulative += v.weight
		if rand_val < cumulative {
			return v.block
		}
	}

	return variants[len(variants)-1].block
}

biome_noise_to_index_threshold :: proc(noise_val: f32) -> int {
	if noise_val < -0.3 do return 0
	if noise_val < 0.4 do return 1
	return 2
}
