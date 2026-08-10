package game

import "core:math"
import "../input"
import "../constants"
import "../renderer"

system_update_lights :: proc(state: ^GameState) {
	// mask := ecs.ComponentMask{.TransformComponent, .LightComponent}

    // gpu_lights := make([dynamic]renderer.LightData, context.temp_allocator)
    // defer delete(gpu_lights)

	// for i in 0 ..< len(state.world.entities) {
	// 	if (state.world.masks[i] & mask) != mask do continue

    //     t := state.world.transforms[i]
    //     l := state.world.lights[i]

    //     append(&gpu_lights, renderer.LightData{
    //         position = t.position,
    //         light_type = u32(l.light_type),
    //         direction = l.direction,
    //         color = l.color,
    //         intensity = l.intensity,
    //         range = l.range,
    //     })
	// }

    // renderer.renderer_update_light_buffer(state.renderer, gpu_lights[:])
}

system_update_sun :: proc(state: ^GameState, dt: f32) {
    state.day_time += 2 * dt * constants.SUN_CYCLE_SPEED

    if (input.is_key_pressed(&state.input, .L)) {
		state.day_time += 2 * dt * 20
		if state.day_time >= 2 * math.PI {
			state.day_time -= 2 * math.PI
		}
	}
}
