package game

import "core:math/linalg"

World :: struct {
	objects:        [dynamic]GameObject,
	next_object_id: u64,
}

world_init :: proc() -> World {
	return {
		objects = make([dynamic]GameObject), //
	}
}

world_create_object :: proc(
	w: ^World,
	mesh: MeshHandle,
	material: MaterialHandle,
	pos: linalg.Vector3f32,
) -> ^GameObject {
	w.next_object_id += 1

	obj := GameObject {
		id = w.next_object_id,
		mesh = mesh,
		material = material,
		transform = {position = pos, scale = {1.0, 1.0, 1.0}},
		active = true,
	}


	append(&w.objects, obj)
	return &w.objects[len(w.objects) - 1]
}
