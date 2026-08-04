package game

import "core:thread"
import "vendor:wgpu"

import "../ecs"
import "../input"
import "../platform"
import "../renderer"

import mu "vendor:microui"

default_shader_src := #load("../assets/shaders/default.wgsl")
chunk_shader_src := #load("../assets/shaders/chunk.wgsl")

teapot_vox := #load("../assets/objects/teapot.vox")
cactus_vox := #load("../assets/objects/cactus.vox")

GameState :: struct {
	assets:   Assets,
	renderer: ^renderer.Renderer,
	input:    input.InputManager,
	world:    ^ecs.World,
	window:   ^platform.Window,
	palette: Palette,
	
	thread_pool: ^thread.Pool,

	mu_ctx: ^mu.Context,
}

game_init :: proc(r: ^renderer.Renderer, window: ^platform.Window, mu_ctx: ^mu.Context) -> GameState {
	assets := assets_init()
	input := input.input_init()
	world := ecs.world_init()
	palette := palette_init_default()
	thread_pool := new(thread.Pool)

	num_cpus := platform.get_num_cores()
	thread.pool_init(thread_pool, context.allocator, num_cpus - 1)
	thread.pool_start(thread_pool)

	return {
		assets = assets,
		renderer = r,
		world = world,
		input = input,
		window = window,
		palette = palette,
		thread_pool = thread_pool,
		mu_ctx = mu_ctx,
	}
}

game_awake :: proc(state: ^GameState) {
	// assets
	default_material := assets_register_material(
		&state.assets,
		"default",
		renderer.material_create(
			state.renderer,
			string(default_shader_src),
			[]wgpu.BindGroupLayout{state.renderer.global_layout_group},
		),
	)
	chunk_material := assets_register_material(
		&state.assets,
		"chunk",
		renderer.material_create(
			state.renderer,
			string(chunk_shader_src),
			[]wgpu.BindGroupLayout{state.renderer.global_layout_group},
		),
	)

	vertices, indices := renderer.quad_geometry()
	quad_mesh := assets_register_mesh(
		&state.assets,
		"quad",
		renderer.mesh_create(state.renderer, vertices, indices),
	)
	// assets

	// quad := ecs.entity_create(state.world)
	// ecs.entity_add_transform(state.world, quad, {})
	// ecs.entity_add_render(
	// 	state.world,
	// 	quad,
	// 	{mesh = string(quad_mesh), material = string(minimal_material)},
	// )

	// light := ecs.entity_create(state.world)
	// ecs.entity_add_transform(state.world, light, {position = {5, 2, 5}, scale = {0.5, 0.5, 0.5}, rotation = linalg.QUATERNIONF32_IDENTITY })
	// ecs.entity_add_light(
	// 	state.world,
	// 	light,
	// 	{
	// 		color = {1, 1, 1},
	// 		intensity = 10,
	// 		light_type = .Point,
	// 		range = 200,
	// 	},
	// )
	// ecs.entity_add_render(
	// 	state.world,
	// 	light,
	// 	{mesh = string(quad_mesh), material = string(default_material)},
	// )

	// light2 := ecs.entity_create(state.world)
	// ecs.entity_add_transform(state.world, light2, {position = {1, 5, 1}, scale = {0.5, 0.5, 0.5}, rotation = linalg.QUATERNIONF32_IDENTITY })
	// ecs.entity_add_light(
	// 	state.world,
	// 	light2,
	// 	{
	// 		color = {1, 1, 1},
	// 		intensity = 10,
	// 		light_type = .Directional,
	// 		direction = {0, -1, 0}
	// 	},
	// )
	// ecs.entity_add_render(
	// 	state.world,
	// 	light2,
	// 	{mesh = string(quad_mesh), material = string(default_material)},
	// )

	assets_register_voxel_prefab(&state.assets, "tree", vox_model_load(teapot_vox))
	assets_register_voxel_prefab(&state.assets, "cactus", vox_model_load(cactus_vox))
	
	spawn_player(state)
	biome_catalog_init(state)
}

game_update :: proc(state: ^GameState, dt: f32) {
	system_physics(state, dt)
	system_update_player(state, dt)
	system_update_lights(state)

	system_chunk_management(state)
	system_resolve_thread_tasks(state)
	system_generate_chunk(state)
	system_generate_chunk_mesh(state)

	if (input.is_key_just_pressed(&state.input, .P)) {
		state.renderer.use_wireframe = !state.renderer.use_wireframe

		// Pipeline needs to be created again to renderer in wireframe mode
		assets_register_material(
			&state.assets,
			"chunk",
			renderer.material_create(
				state.renderer,
				string(chunk_shader_src),
				[]wgpu.BindGroupLayout{state.renderer.global_layout_group},
			),
		)
		assets_register_material(
			&state.assets,
			"default",
			renderer.material_create(
				state.renderer,
				string(default_shader_src),
				[]wgpu.BindGroupLayout{state.renderer.global_layout_group},
			),
		)
	}
	if (input.is_key_just_pressed(&state.input, .Escape)) {
		state.window.terminate = true
	}
	if (input.is_key_just_pressed(&state.input, .LeftAlt)) {
		platform.toggle_cursor(state.window)
	}

	input.input_update(&state.input)

	microui_update(state, dt)
}

game_destroy :: proc(state: ^GameState) {
	assets_destroy(&state.assets)

	thread.pool_join(state.thread_pool)
	thread.pool_destroy(state.thread_pool)
	free(state.thread_pool)
	free(state.mu_ctx)
}
