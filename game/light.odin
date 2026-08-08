package game

import "core:math/linalg"
import "../ecs"
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
