package game

import "core:math/linalg"

import "../ecs"
import "../renderer"
import "../constants"

game_get_render_items :: proc(state: ^GameState) -> []renderer.RenderItem {
	items := make([dynamic]renderer.RenderItem, context.temp_allocator)
	required_mask := ecs.ComponentMask{.TransformComponent, .RenderComponent}

	cam_matrix := game_get_camera_matrix(state)
	frustum := frustum_extract(cam_matrix)

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & required_mask) != required_mask do continue

		t := state.world.transforms[i]
		r := state.world.renders[i]

		is_chunk := (state.world.masks[i] & ecs.ComponentMask{.ChunkComponent}) == ecs.ComponentMask{.ChunkComponent}

		local_aabb: AABB
		if is_chunk {
			local_aabb = AABB{
				min = {0, 0, 0},
				max = {f32(constants.CHUNK_SIZE), f32(constants.CHUNK_SIZE), f32(constants.CHUNK_SIZE)}
			}
		} else {
			local_aabb = AABB{
				min = {-1, -1, -1},
				max = {1, 1, 1}
			}
		}

		m := transform_matrix(t)
		world_aabb := aabb_transform(local_aabb, m)

		if !aabb_in_frustum(world_aabb, frustum) do continue

		mesh_ptr := assets_get_mesh(&state.assets, MeshHandle(r.mesh))
		mat_ptr := assets_get_material(&state.assets, MaterialHandle(r.material))

		append(&items, renderer.RenderItem{mesh = mesh_ptr, material = mat_ptr, transform = m, should_use_instance = !r.ignore_instancing})
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
