package game

import "../ecs"
import "../platform"
import "../input"
import "core:math/linalg"

spawn_player :: proc(state: ^GameState) {
	width, height := platform.get_frame_size(state.window)
	player := ecs.entity_create(state.world)
	ecs.entity_add_transform(
		state.world,
		player,
		{position = {0, 20, 0}, rotation = linalg.QUATERNIONF32_IDENTITY, scale = {1, 1, 1}},
	)
	ecs.entity_add_physics(state.world, player, { friction = 8.0 })
	ecs.entity_add_collider(state.world, player, {
        size = {0.6, 1.8, 0.6},
        offset = {0, 0.9, 0}
    })
	ecs.entity_add_first_person(
		state.world,
		player,
		{sensitivity = 0.1, pitch = 0, yaw = 0, speed = 60},
	)
	ecs.entity_add_camera(
		state.world,
		player,
		{
            offset = {0, 1.6, 0},
			target = {0, 0, 0},
			up = {0, 1, 0},
			aspect = f32(width) / f32(height),
			fovy = 90 * linalg.RAD_PER_DEG,
			zfar = 100 + f32(state.world.render_distance * 10),
			znear = 0.1,
		},
	)

	ecs.entity_disable_components(state.world, player, {.PhysicsComponent})
}

system_update_player :: proc(state: ^GameState, dt: f32) {
	mask := ecs.ComponentMask{.TransformComponent, .CameraComponent, .FirstPersonComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) != mask do continue
		has_physics := (state.world.masks[i] & ecs.ComponentMask{.PhysicsComponent}) == {.PhysicsComponent}

		// TODO: Maybe this is not the better place to change the player mask
		if input.is_key_just_pressed(&state.input, .F) {
			entity := state.world.entities[i]

			if has_physics do ecs.entity_disable_components(state.world, entity, {.PhysicsComponent})
			else do ecs.entity_enable_components(state.world, entity, {.PhysicsComponent})

			continue
		}

		t := &state.world.transforms[i]
		cam := &state.world.cameras[i]
		fps := &state.world.first_persons[i]
		p := &state.world.physics[i]

		speed := has_physics ? fps.speed : fps.speed / 4

		fps.yaw += state.input.mouse_dx * fps.sensitivity
		fps.pitch -= state.input.mouse_dy * fps.sensitivity

		if fps.pitch > 89.0 {
			fps.pitch = 89.0
		}
		if fps.pitch < -89.0 {
			fps.pitch = -89.0
		}

		yaw_rad := fps.yaw * linalg.RAD_PER_DEG
		pitch_rad := fps.pitch * linalg.RAD_PER_DEG

		forward: linalg.Vector3f32
		forward.x = linalg.cos(yaw_rad) * linalg.cos(pitch_rad)
		forward.y = linalg.sin(pitch_rad)
		forward.z = linalg.sin(yaw_rad) * linalg.cos(pitch_rad)
		forward = linalg.normalize(forward)

		right := linalg.normalize(linalg.cross(forward, linalg.Vector3f32{0.0, 1.0, 0.0}))
		up := linalg.Vector3f32{0.0, 1.0, 0.0}

		input_dir: linalg.Vector3f32

		if input.is_key_pressed(&state.input, .W) do input_dir.z += 1
		if input.is_key_pressed(&state.input, .S) do input_dir.z -= 1
		if input.is_key_pressed(&state.input, .A) do input_dir.x -= 1
		if input.is_key_pressed(&state.input, .D) do input_dir.x += 1
		if input.is_key_pressed(&state.input, .Space) && !has_physics do input_dir.y += 1
		if input.is_key_pressed(&state.input, .LeftShift) && !has_physics do input_dir.y -= 1
		if input.is_key_just_pressed(&state.input, .Space) && has_physics {
			if p.is_grounded {
				p.velocity.y = 6.0
				p.is_grounded = false
			}
		}

		if linalg.length(input_dir) > 0 {
			input_dir = linalg.normalize(input_dir)
		}

		if has_physics {
			flat_forward := linalg.Vector3f32{forward.x, 0.0, forward.z}
			if linalg.length(flat_forward) > 0 {
				flat_forward = linalg.normalize(flat_forward)
			}
			
			move_dir := (flat_forward * input_dir.z) + (right * input_dir.x)
			if linalg.length(move_dir) > 0 {
				move_dir = linalg.normalize(move_dir)
			}

			p.velocity.x += move_dir.x * speed * dt
			p.velocity.z += move_dir.z * speed * dt
		} else {
			t.position += forward * input_dir.z * speed * dt
			t.position += right * input_dir.x * speed * dt
			t.position += up * input_dir.y * speed * dt
		}

		cam.target = t.position + forward
	}
}
