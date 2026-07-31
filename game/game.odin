package game

import "../renderer"
import "vendor:wgpu"

default_shader_src := #load("../assets/shaders/minimal.wgsl")

GameState :: struct {
	assets:   Assets,
	renderer: ^renderer.Renderer,
	world:    World,
}

game_init :: proc(r: ^renderer.Renderer) -> GameState {
	assets := assets_init()

	minimal_material := assets_register_material(
		&assets,
		"minimal",
		renderer.material_create(
			r,
			string(default_shader_src),
			renderer.vertex_get_buffer_layout(),
			[]wgpu.BindGroupLayout{r.camera.bind_group_layout},
		),
	)

	vertices, indices := renderer.quad_geometry()
	quad_mesh := assets_register_mesh(&assets, "quad", renderer.mesh_create(r, vertices, indices))

	world := world_init()

	world_create_object(&world, quad_mesh, minimal_material, {0, 0, 0})

	return {assets = assets, renderer = r, world = world}
}

game_update :: proc(state: ^GameState, dt: f32) {}

game_destroy :: proc(state: ^GameState) {
	assets_destroy(&state.assets)
}

game_get_render_items :: proc(state: ^GameState) -> []renderer.RenderItem {
	items := make([dynamic]renderer.RenderItem, context.temp_allocator)

	for obj in state.world.objects {
		if !obj.active do continue

		mesh := assets_get_mesh(&state.assets, obj.mesh)
		material := assets_get_material(&state.assets, obj.material)

		append(&items, renderer.RenderItem{mesh = mesh, material = material})
	}

	return items[:]
}
