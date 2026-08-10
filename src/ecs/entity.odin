package ecs

Entity :: distinct u64

entity_make :: proc(index: u32, generation: u32) -> Entity {
	return Entity(u64(generation) << 32 | u64(index))
}

entity_index :: proc(e: Entity) -> u32 {
	return u32(u64(e) & 0xFFFFFFFF)
}

entity_generation :: proc(e: Entity) -> u32 {
	return u32(u64(e) >> 32)
}
