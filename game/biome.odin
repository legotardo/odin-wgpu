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

BiomeConfig :: struct {
	id:                BiomeType,
	name:              string,
	surface_blocks:    []BlockVariant,
	sub_surface_block: ecs.Block,
	sub_surface_depth: i32,
	base_block:        ecs.Block,
}

BIOME_ZONES :: 3

biome_matrix: [BIOME_ZONES][BIOME_ZONES]BiomeType = {
	// TEMP: Frio       | Temperado  | Quente
	{.Plains, .Plains, .Desert}, // UMIDADE: Seco
	{.Plains, .Plains, .Desert}, // UMIDADE: Médio
	{.Plains, .Plains, .Plains}, // UMIDADE: Úmido
}

biome_catalog: [len(BiomeType)]BiomeConfig

biome_catalog_init :: proc() {
    plains_surface := make([]BlockVariant, 3)
    plains_surface[0] = {block = .Grass1, weight = 93}
    plains_surface[1] = {block = .Grass2, weight = 5}
    plains_surface[2] = {block = .Grass3, weight = 2}

    biome_catalog[BiomeType.Plains] = BiomeConfig{
        id = .Plains,
        name = "Plains",
        surface_blocks = plains_surface,
        sub_surface_block = .Grass1,
        sub_surface_depth = 4,
        base_block = .Grass1,
    }

    desert_surface := make([]BlockVariant, 1)
    desert_surface[0] = {block = .Sand1, weight = 100}

    biome_catalog[BiomeType.Desert] = BiomeConfig{
        id = .Desert,
        name = "Desert",
        surface_blocks = desert_surface,
        sub_surface_block = .Sand1,
        sub_surface_depth = 4,
        base_block = .Sand1,
    }
}

// https://github.com/aappleby/smhasher/blob/master/src/MurmurHash3.cpp
@(private="file")
spatial_hash :: proc(x, y, z: i32) -> u32 {
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

biome_get_variant_block :: proc(variants: []BlockVariant, world_x, world_y, world_z: i32) -> ecs.Block {
	if len(variants) == 0 do return .Air
	if len(variants) == 1 do return variants[0].block

	hash_val := spatial_hash(world_x, world_y, world_z)
	
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
