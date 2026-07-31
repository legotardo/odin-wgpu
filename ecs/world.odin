package ecs

MAX_ENTITIES :: 10000

ComponentType :: enum {
	Transform,
	Render,
}

ComponentMask :: bit_set[ComponentType]

World :: struct {
	entities:           [dynamic]Entity,
	entity_generations: [MAX_ENTITIES]u32,
	free_indices:       [dynamic]u32,
	masks:              [MAX_ENTITIES]ComponentMask,
	transforms:         [MAX_ENTITIES]Transform,
	renders:            [MAX_ENTITIES]Render,
}

world_init :: proc(allocator := context.allocator) -> ^World {
	world := new(World, allocator)

	world.entities = make([dynamic]Entity, allocator)
	world.free_indices = make([dynamic]u32, allocator)

	return world
}

world_destroy :: proc(w: ^World) {
	delete(w.entities)
	delete(w.free_indices)
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

entity_add_transform :: proc(w: ^World, e: Entity, t: Transform) {
	idx := entity_index(e)
	w.transforms[idx] = t
	w.masks[idx] += {.Transform}
}

entity_add_render :: proc(w: ^World, e: Entity, r: Render) {
	idx := entity_index(e)
	w.renders[idx] = r
	w.masks[idx] += {.Render}
}
