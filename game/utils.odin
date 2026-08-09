package game

import "core:math"
import "core:math/linalg"

import "../ecs"
import "../renderer"
import "../constants"
import "../shared"

game_get_render_items :: proc(
	state: ^GameState,
	shadow_view_proj: linalg.Matrix4f32,
) -> []renderer.RenderItem {
	items := make([dynamic]renderer.RenderItem)
	required_mask := ecs.ComponentMask{.TransformComponent, .RenderComponent}
	chunk_mask := ecs.ComponentMask{.ChunkComponent}

	cam_matrix := game_get_camera_matrix(state)
	camera_frustum := frustum_extract(cam_matrix)
	shadow_frustum := frustum_extract(shadow_view_proj)

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

		visible_in_camera := aabb_in_frustum(world_aabb, camera_frustum)
		visible_in_shadow := aabb_in_frustum(world_aabb, shadow_frustum)
		if !visible_in_camera && !visible_in_shadow do continue

		mesh_ptr := assets_get_mesh(&state.assets, MeshHandle(r.mesh))

		mat_ptr := chunk_material
		if !is_chunk {
			mat_ptr = assets_get_material(&state.assets, MaterialHandle(r.material))
		}

		if mesh_ptr == nil || mat_ptr == nil do continue

		append(&items, renderer.RenderItem{
			mesh = mesh_ptr,
			material = mat_ptr,
			transform = m,
			should_use_instance = !r.ignore_instancing,
			visible_in_camera = visible_in_camera,
		})
	}

	return items[:]
}

game_get_camera_components :: proc(state: ^GameState) -> (t: ecs.TransformComponent, c: ecs.CameraComponent, found: bool) {
	mask := ecs.ComponentMask{.TransformComponent, .CameraComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) == mask {
			return state.world.transforms[i], state.world.cameras[i], true
		}
	}

	return {}, {}, false
}

game_get_camera_matrix :: proc(state: ^GameState) -> linalg.Matrix4f32 {
	t, c, found := game_get_camera_components(state)
	if !found do return linalg.MATRIX4F32_IDENTITY

	eye_pos := t.position + c.offset
	view := linalg.matrix4_look_at_f32(eye_pos, c.target + c.offset, c.up)
	proj := linalg.matrix4_perspective_f32(c.fovy, c.aspect, c.znear, c.zfar)

	return proj * view
}

game_get_camera_eye :: proc(state: ^GameState) -> linalg.Vector3f32 {
	t, c, found := game_get_camera_components(state)
	if found do return t.position + c.offset
	return {}
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

game_calculate_sun :: proc(
	state: ^GameState,
	player_pos: linalg.Vector3f32,
) -> renderer.SunUniform {
	sun_angle := state.day_time
	sun_dir := linalg.vector_normalize(linalg.Vector3f32{
		math.cos(sun_angle),
		math.sin(sun_angle),
		-0.3,
	})

	sun_height := sun_dir.y

	min_elevation_rad: f32 = 10.0 * math.PI / 180.0
	min_height := math.sin(min_elevation_rad)

	shadow_dir := sun_dir
	if shadow_dir.y < min_height {
		shadow_dir.y = min_height
		shadow_dir = linalg.vector_normalize(shadow_dir)
	}

	norm_dir := shadow_dir

	ortho_size := constants.SHADOW_ORTHO_HALF_SIZE
	resolution := f32(constants.SHADOW_MAP_SIZE)
	texel_size := (ortho_size * 2.0) / resolution
	forward := -norm_dir
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
	sun_pos := snapped_target + (norm_dir * 500.0)

	view := linalg.matrix4_look_at_f32(sun_pos, snapped_target, up)
	projection := matrix_ortho3d_f32_d3d(
		-ortho_size, ortho_size, -ortho_size, ortho_size,
		0.1, 1000.0
	)

	day_zenith, day_horizon := game_get_blended_biome_sky(state, player_pos)

	night_zenith := linalg.Vector3f32{0.006, 0.010, 0.030}
	night_horizon := linalg.Vector3f32{0.015, 0.025, 0.060}
	twilight_zenith := linalg.Vector3f32{0.10, 0.12, 0.24}
	twilight_horizon := linalg.Vector3f32{0.90, 0.30, 0.08}

	day_blend := smoothstep(-0.12, 0.22, sun_height)
	twilight_rise := smoothstep(-0.32, -0.02, sun_height)
	twilight_fall := 1.0 - smoothstep(0.08, 0.38, sun_height)
	twilight_blend := twilight_rise * twilight_fall

	current_zenith := linalg.lerp(night_zenith, day_zenith, day_blend)
	current_horizon := linalg.lerp(night_horizon, day_horizon, day_blend)
	current_zenith = linalg.lerp(current_zenith, twilight_zenith, twilight_blend * 0.65)
	current_horizon = linalg.lerp(current_horizon, twilight_horizon, twilight_blend * 0.85)

	return {
		direction = {sun_dir.x, sun_dir.y, sun_dir.z, sun_height},
		view_proj = projection * view,
		sky_horizon = {current_horizon.x, current_horizon.y, current_horizon.z, 1.0},
		sky_zenith = {current_zenith.x, current_zenith.y, current_zenith.z, 1.0},
	}
}

@(private="file")
get_chunk_biome_sky :: proc(
	state: ^GameState,
	chunk_x, reference_y, chunk_z: i32,
) -> (zenith, horizon: linalg.Vector3f32, found: bool) {
	directions := [2]i32{-1, 1}
	for distance in 0 ..= state.world.render_distance {
		for direction in directions {
			if distance == 0 && direction == 1 do continue

			chunk_y := reference_y
			if distance > 0 {
				chunk_y += distance * direction
			}

			chunk_idx := world_get_chunk_at(state.world, {chunk_x, chunk_y, chunk_z})
			if chunk_idx < 0 do continue

			chunk := &state.world.chunks[chunk_idx]
			if chunk.state != .Done do continue

			weight_sum: f32
			for biome_idx in 0 ..< len(shared.BiomeType) {
				weight := chunk.biome_weights[biome_idx]
				if weight <= 0 do continue

				biome := &biome_catalog[shared.BiomeType(biome_idx)]
				zenith += biome.zenith_day * weight
				horizon += biome.horizon_day * weight
				weight_sum += weight
			}

			if weight_sum > 0 {
				return zenith / weight_sum, horizon / weight_sum, true
			}
		}
	}

	return {}, {}, false
}

@(private="file")
game_get_blended_biome_sky :: proc(
	state: ^GameState,
	player_pos: linalg.Vector3f32,
) -> (zenith, horizon: linalg.Vector3f32) {
	default_zenith := linalg.Vector3f32{0.15, 0.45, 0.85}
	default_horizon := linalg.Vector3f32{0.55, 0.75, 0.95}
	cs_world := f32(constants.CHUNK_SIZE) * constants.BLOCK_SIZE

	grid_x := player_pos.x / cs_world - 0.5
	grid_z := player_pos.z / cs_world - 0.5
	base_x := i32(math.floor(grid_x))
	base_z := i32(math.floor(grid_z))
	chunk_y := i32(math.floor(player_pos.y / cs_world))
	tx := grid_x - f32(base_x)
	tz := grid_z - f32(base_z)

	weights := [4]f32{
		(1.0 - tx) * (1.0 - tz),
		tx * (1.0 - tz),
		(1.0 - tx) * tz,
		tx * tz,
	}
	coords := [4][2]i32{
		{base_x, base_z},
		{base_x + 1, base_z},
		{base_x, base_z + 1},
		{base_x + 1, base_z + 1},
	}

	weight_sum: f32
	for coord, sample_idx in coords {
		sample_zenith, sample_horizon, found := get_chunk_biome_sky(
			state, coord.x, chunk_y, coord.y,
		)
		if !found do continue

		weight := weights[sample_idx]
		zenith += sample_zenith * weight
		horizon += sample_horizon * weight
		weight_sum += weight
	}

	if weight_sum <= 0 {
		return default_zenith, default_horizon
	}

	return zenith / weight_sum, horizon / weight_sum
}

@(private="file")
smoothstep :: proc "contextless" (edge0, edge1, x: f32) -> f32 {
	t := clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
}

matrix_ortho3d_f32_d3d :: proc "contextless" (left, right, bottom, top, near, far: f32) -> linalg.Matrix4f32 #no_bounds_check {
	// https://learn.microsoft.com/en-us/windows/win32/direct3d9/d3dxmatrixorthooffcenterlh#remarks
	// linalg library uses OpenGL standard (-1.0, 1.0) but wgpu uses DirectX (0.0, 1.0)
	return {
		+2 / (right - left), 0, 0, 0,
		0, +2 / (top - bottom), 0, 0,
		0, 0, +1 / (near - far),   0,
		(left + right) / (left - right), (top + bottom) / (bottom - top), near / (near - far), 1
	}
}

transform_matrix :: proc(t: ecs.TransformComponent) -> matrix[4, 4]f32 {
	model := linalg.matrix4_from_trs_f32(t.position, t.rotation, t.scale)

	return model
}
