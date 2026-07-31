package game

import "../ecs"
import "../input"
import "core:math/linalg"

system_update_camera :: proc(state: ^GameState, dt: f32) {
	mask := ecs.ComponentMask{.TransformComponent, .CameraComponent, .FirstPersonComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) != mask do continue

		t := &state.world.transforms[i]
		cam := &state.world.cameras[i]
		fps := &state.world.first_persons[i]

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
		if input.is_key_pressed(&state.input, .Space) do input_dir.y += 1
		if input.is_key_pressed(&state.input, .LeftShift) do input_dir.y -= 1

		if linalg.length(input_dir) > 0 {
			input_dir = linalg.normalize(input_dir)
		}

		t.position += forward * input_dir.z * fps.speed * dt
		t.position += right * input_dir.x * fps.speed * dt
		t.position += up * input_dir.y * fps.speed * dt

		cam.target = t.position + forward
	}
}
