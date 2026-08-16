package game

import "core:math"
import "../ecs"
import "../constants"
import "core:math/linalg"

system_physics :: proc(state: ^GameState, dt: f32) {
	mask := ecs.ComponentMask{.TransformComponent, .PhysicsComponent, .ColliderComponent}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & mask) != mask do continue

		t := &state.world.transforms[i]
		p := &state.world.physics[i]
		c := &state.world.colliders[i]
		did_auto_step := false

        p.velocity.y -= constants.GRAVITY * dt

        friction: f32 = p.friction
        if !p.is_grounded {
            friction /= 2
        }

        p.velocity.x -= p.velocity.x * friction * dt
		p.velocity.z -= p.velocity.z * friction * dt

        // TODO: Maybe relative to the mass
        max_speed: f32 = 4.0
        horizontal_speed := math.sqrt(p.velocity.x * p.velocity.x + p.velocity.z * p.velocity.z)

        if horizontal_speed > max_speed {
            ratio := max_speed / horizontal_speed
            p.velocity.x *= ratio
            p.velocity.z *= ratio
        }

        if math.abs(p.velocity.x) < 0.01 do p.velocity.x = 0
		if math.abs(p.velocity.z) < 0.01 do p.velocity.z = 0

        t.position.y += p.velocity.y * dt
        if world_check_collision(state.world, aabb_by_collider(t.position, c)) {
            t.position.y -= p.velocity.y * dt
            if p.velocity.y < 0 {
                p.is_grounded = true
            }
            p.velocity.y = 0
        } else {
            p.is_grounded = false
        }

		// TODO: Maybe move this to another place
		can_auto_step := u32(i) == state.player_idx && p.is_grounded

		t.position.x += p.velocity.x * dt
		if world_check_collision(state.world, aabb_by_collider(t.position, c)) {
			if can_auto_step {
				t.position.y += PLAYER_AUTO_STEP_HEIGHT
				if world_check_collision(state.world, aabb_by_collider(t.position, c)) {
					t.position.y -= PLAYER_AUTO_STEP_HEIGHT
					t.position.x -= p.velocity.x * dt
					p.velocity.x = 0
				} else {
					did_auto_step = true
					p.velocity.y = 0
				}
			} else {
				t.position.x -= p.velocity.x * dt
				p.velocity.x = 0
			}
		}
		t.position.z += p.velocity.z * dt
		if world_check_collision(state.world, aabb_by_collider(t.position, c)) {
			if can_auto_step && !did_auto_step {
				t.position.y += PLAYER_AUTO_STEP_HEIGHT
				if world_check_collision(state.world, aabb_by_collider(t.position, c)) {
					t.position.y -= PLAYER_AUTO_STEP_HEIGHT
					t.position.z -= p.velocity.z * dt
					p.velocity.z = 0
				} else {
					did_auto_step = true
					p.velocity.y = 0
				}
			} else {
				t.position.z -= p.velocity.z * dt
				p.velocity.z = 0
			}
		}

		if did_auto_step {
			state.world.cameras[i].visual_offset.y -= PLAYER_AUTO_STEP_HEIGHT
		}
    }
}
