package ecs

import "core:sync"
MAX_ENTITIES :: 100000

ComponentType :: enum {
	TransformComponent,
	RenderComponent,
	CameraComponent,
	FirstPersonComponent,
	ChunkComponent,
	LightComponent,
	PhysicsComponent,
	ColliderComponent,
}

ComponentMask :: bit_set[ComponentType]

World :: struct {
	entities:           [dynamic]Entity,
	entity_generations: [MAX_ENTITIES]u32,
	free_indices:       [dynamic]u32,
	masks:              [MAX_ENTITIES]ComponentMask,

	// Components
	transforms:         [MAX_ENTITIES]TransformComponent,
	renders:            [MAX_ENTITIES]RenderComponent,
	first_persons:      [MAX_ENTITIES]FirstPersonComponent,
	chunks:             [MAX_ENTITIES]ChunkComponent,
	lights:             [MAX_ENTITIES]LightComponent,
	physics:            [MAX_ENTITIES]PhysicsComponent,
	colliders:          [MAX_ENTITIES]ColliderComponent,
	cameras:            [1]CameraComponent,

	chunk_map: map[[3]i32]int,
	chunk_spawn_offset: [dynamic]ChunkOffset,
	chunk_missing_blocks: map[ChunkPos][dynamic]ChunkMissingBlock,
	chunk_missing_blocks_mu: sync.Mutex,

	render_distance: i32,
}

world_init :: proc(allocator := context.allocator) -> ^World {
	world := new(World, allocator)

	world.entities = make([dynamic]Entity, allocator)
	world.free_indices = make([dynamic]u32, allocator)
	world.chunk_missing_blocks = make(map[ChunkPos][dynamic]ChunkMissingBlock, allocator)

	return world
}

world_destroy :: proc(w: ^World) {
	mask_chunk := ComponentMask{.ChunkComponent}
	for i in 0 ..< len(w.entities) {
		if (w.masks[i] & mask_chunk) == mask_chunk {
			delete(w.chunks[i].palette)
			delete(w.chunks[i].packed_blocks)
		}
	}

	delete(w.entities)
	delete(w.free_indices)
	delete(w.chunk_map)
	delete(w.chunk_spawn_offset)
	for _, list in w.chunk_missing_blocks {
		delete(list)
	}
	delete(w.chunk_missing_blocks)
	free(w)
}

entity_create :: proc(w: ^World) -> Entity {
	index: u32
	generation: u32

	if len(w.free_indices) > 0 {
		index = pop(&w.free_indices)
		generation = w.entity_generations[index]
	} else {
		index = u32(len(w.entities))
		generation = 1
		w.entity_generations[index] = generation
		append(&w.entities, 0)
	}

	e := entity_make(index, generation)
	w.entities[index] = e
	w.masks[index] = {}

	return e
}

entity_destroy :: proc(w: ^World, e: Entity) {
	idx := entity_index(e)

	if w.entity_generations[idx] != entity_generation(e) do return

	w.entity_generations[idx] += 1
	w.masks[idx] = {}
	append(&w.free_indices, idx)
}

entity_disable_components :: proc(w: ^World, e: Entity, m: ComponentMask) {
	idx := entity_index(e)
	w.masks[idx] -= m
}

entity_enable_components :: proc(w: ^World, e: Entity, m: ComponentMask) {
	idx := entity_index(e)
	w.masks[idx] += m
}

entity_add_transform :: proc(w: ^World, e: Entity, c: TransformComponent) {
	idx := entity_index(e)
	w.transforms[idx] = c
	w.masks[idx] += {.TransformComponent}
}

entity_add_render :: proc(w: ^World, e: Entity, c: RenderComponent) {
	idx := entity_index(e)
	w.renders[idx] = c
	w.masks[idx] += {.RenderComponent}
}

entity_add_camera :: proc(w: ^World, e: Entity, c: CameraComponent) {
	idx := entity_index(e)
	w.cameras[idx] = c
	w.masks[idx] += {.CameraComponent}
}

entity_add_first_person :: proc(w: ^World, e: Entity, c: FirstPersonComponent) {
	idx := entity_index(e)
	w.first_persons[idx] = c
	w.masks[idx] += {.FirstPersonComponent}
}

entity_add_chunk :: proc(w: ^World, e: Entity, c: ChunkComponent) {
	idx := entity_index(e)
	w.chunks[idx] = c
	w.masks[idx] += {.ChunkComponent}
}

entity_add_light :: proc(w: ^World, e: Entity, c: LightComponent) {
	idx := entity_index(e)
	w.lights[idx] = c
	w.masks[idx] += {.LightComponent}
}

entity_add_physics :: proc(w: ^World, e: Entity, c: PhysicsComponent) {
	idx := entity_index(e)
	w.physics[idx] = c
	w.masks[idx] += {.PhysicsComponent}
}

entity_add_collider :: proc(w: ^World, e: Entity, c: ColliderComponent) {
	idx := entity_index(e)
	w.colliders[idx] = c
	w.masks[idx] += {.ColliderComponent}
}
