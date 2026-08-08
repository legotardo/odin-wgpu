package game

import "core:math"
import "core:math/linalg"

import "../ecs"
import "../renderer"
import "../constants"

game_get_render_items :: proc(state: ^GameState) -> []renderer.RenderItem {
	items := make([dynamic]renderer.RenderItem)
	required_mask := ecs.ComponentMask{.TransformComponent, .RenderComponent}
	chunk_mask := ecs.ComponentMask{.ChunkComponent}

	cam_matrix := game_get_camera_matrix(state)
	frustum := frustum_extract(cam_matrix)

	chunk_aabb := AABB{
		min = {0, 0, 0},
		max = {f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE, f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE, f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE}
	}

	chunk_material := assets_get_material(&state.assets, MaterialHandle("chunk"))

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & required_mask) != required_mask do continue

		t := state.world.transforms[i]
		r := state.world.renders[i]

		is_chunk := (state.world.masks[i] & chunk_mask) == chunk_mask

		world_aabb: AABB
		m: linalg.Matrix4f32
		if is_chunk {
			world_aabb = AABB{min = chunk_aabb.min + t.position, max = chunk_aabb.max + t.position}
			m = linalg.matrix4_translate_f32(t.position)
		} else {
			m = transform_matrix(t)
			world_aabb = aabb_transform(AABB{min = {-1, -1, -1}, max = {1, 1, 1}}, m)
		}

		if !aabb_in_frustum(world_aabb, frustum) do continue

		mesh_ptr := assets_get_mesh(&state.assets, MeshHandle(r.mesh))

		mat_ptr := chunk_material
		if !is_chunk {
			mat_ptr = assets_get_material(&state.assets, MaterialHandle(r.material))
		}

		if mesh_ptr == nil || mat_ptr == nil do continue

		append(&items, renderer.RenderItem{mesh = mesh_ptr, material = mat_ptr, transform = m, should_use_instance = !r.ignore_instancing})
	}

	return items[:]
}

game_get_camera_matrix :: proc(state: ^GameState) -> linalg.Matrix4f32 {
	mask := ecs.ComponentMask{.TransformComponent, .CameraComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) == mask {
			t := state.world.transforms[i]
			c := state.world.cameras[i]

			eye_pos := t.position + c.offset

			view := linalg.matrix4_look_at_f32(eye_pos, c.target + c.offset, c.up)
			proj := linalg.matrix4_perspective_f32(c.fovy, c.aspect, c.znear, c.zfar)

			return proj * view
		}
	}

	return linalg.MATRIX4F32_IDENTITY
}

game_get_camera_eye :: proc(state: ^GameState) -> linalg.Vector3f32 {
	mask := ecs.ComponentMask{.TransformComponent, .CameraComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) == mask {
			t := state.world.transforms[i]
			c := state.world.cameras[i]

			return t.position + c.offset
		}
	}

	return { }
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

game_calculate_sun :: proc(player_pos: linalg.Vector3f32, sun_dir: linalg.Vector3f32) -> renderer.SunUniform {
	norm_dir := linalg.vector_normalize(sun_dir)
	
	ortho_size: f32 = 100.0
	resolution: f32 = 8192.0
	texel_size := (ortho_size * 2.0) / resolution

	forward := norm_dir
	up_ref := linalg.Vector3f32{0.0, 1.0, 0.0}
	
	right := linalg.vector_normalize(linalg.vector_cross(up_ref, forward))
	up := linalg.vector_normalize(linalg.vector_cross(forward, right))

	proj_x := linalg.vector_dot(player_pos, right)
	proj_y := linalg.vector_dot(player_pos, up)

	snapped_x := math.floor(proj_x / texel_size) * texel_size
	snapped_y := math.floor(proj_y / texel_size) * texel_size

	dx := snapped_x - proj_x
	dy := snapped_y - proj_y

	snapped_target := player_pos + (right * dx) + (up * dy)
	sun_pos := snapped_target - (norm_dir * 500.0)
	
	view_matrix := linalg.matrix4_look_at_f32(sun_pos, snapped_target, {0.0, 1.0, 0.0})

	world_height: f32 = 80.0
	vertical := linalg.Vector3f32{0.0, world_height, 0.0}

	near_z: f32 = math.F32_MAX
	far_z: f32 = math.F32_MIN

	corners := [8]linalg.Vector3f32{
		right * ortho_size + up * ortho_size + vertical,
		right * ortho_size + up * ortho_size - vertical,
		right * ortho_size - up * ortho_size + vertical,
		right * ortho_size - up * ortho_size - vertical,
		-right * ortho_size + up * ortho_size + vertical,
		-right * ortho_size + up * ortho_size - vertical,
		-right * ortho_size - up * ortho_size + vertical,
		-right * ortho_size - up * ortho_size - vertical,
	}

	for corner in corners {
		z := linalg.vector_dot(snapped_target + corner - sun_pos, forward)
		near_z = math.min(near_z, z)
		far_z = math.max(far_z, z)
	}

	near: f32 = math.max(near_z, 1.0)
	far: f32 = math.max(far_z, near + 100.0)

	proj_matrix := linalg.MATRIX4F32_IDENTITY
	proj_matrix[0, 0] = 1.0 / ortho_size
	proj_matrix[1, 1] = 1.0 / ortho_size
	proj_matrix[2, 2] = 1.0 / (near - far)
	proj_matrix[2, 3] = near / (near - far)

	return {
		view_proj = proj_matrix * view_matrix,
		direction = {norm_dir.x, norm_dir.y, norm_dir.z, 0.0},
	}
}

transform_matrix :: proc(t: ecs.TransformComponent) -> matrix[4, 4]f32 {
	model := linalg.matrix4_from_trs_f32(t.position, t.rotation, t.scale)

	return model
}
