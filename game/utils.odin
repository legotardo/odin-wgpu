package game

import "core:math/linalg"

import "../ecs"
import "../renderer"

game_get_render_items :: proc(state: ^GameState) -> []renderer.RenderItem {
	items := make([dynamic]renderer.RenderItem, context.temp_allocator)
	required_mask := ecs.ComponentMask{.Transform, .Render}

	for i in 0 ..< len(state.world.entities) {
		if (state.world.masks[i] & required_mask) == required_mask {
			t := state.world.transforms[i]
			r := state.world.renders[i]

			mesh_ptr := assets_get_mesh(&state.assets, MeshHandle(r.mesh))
			mat_ptr := assets_get_material(&state.assets, MaterialHandle(r.material))
			m := transform_matrix(t)

			append(&items, renderer.RenderItem{mesh = mesh_ptr, material = mat_ptr})
		}
	}

	return items[:]
}

transform_matrix :: proc(t: ecs.Transform) -> linalg.Matrix4f32 {
	m_pos := linalg.matrix4_translate_f32(t.position)
	m_scale := linalg.matrix4_scale(t.scale)

	return m_pos * m_scale
}
