package game

import "core:math/linalg"

import "../ecs"
import "../renderer"

game_get_render_items :: proc(state: ^GameState) -> []renderer.RenderItem {
	items := make([dynamic]renderer.RenderItem, context.temp_allocator)
	required_mask := ecs.ComponentMask{.TransformComponent, .RenderComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & required_mask) != required_mask do continue

		t := state.world.transforms[i]
		r := state.world.renders[i]

		mesh_ptr := assets_get_mesh(&state.assets, MeshHandle(r.mesh))
		mat_ptr := assets_get_material(&state.assets, MaterialHandle(r.material))
		m := transform_matrix(t)

		append(&items, renderer.RenderItem{mesh = mesh_ptr, material = mat_ptr, transform = m})
	}

	// fmt.printf("Items to render = %d\n", len(items))

	return items[:]
}

game_get_camera_matrix :: proc(state: ^GameState) -> linalg.Matrix4f32 {
	mask := ecs.ComponentMask{.TransformComponent, .CameraComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) == mask {
			t := state.world.transforms[i]
			c := state.world.cameras[i]

			view := linalg.matrix4_look_at_f32(t.position, c.target, c.up)
			proj := linalg.matrix4_perspective_f32(c.fovy, c.aspect, c.znear, c.zfar)

			return proj * view
		}
	}

	return linalg.MATRIX4F32_IDENTITY
}

game_update_camera_component :: proc(state: ^GameState, width, height: u32) {
	mask := ecs.ComponentMask{.CameraComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) == mask {
			c := &state.world.cameras[i]

			c.aspect = f32(width) / f32(height)
		}
	}
}

transform_matrix :: proc(t: ecs.TransformComponent) -> matrix[4, 4]f32 {
	model := linalg.matrix4_from_trs_f32(t.position, t.rotation, t.scale)

	return model
}
