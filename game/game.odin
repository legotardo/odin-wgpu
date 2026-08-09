package game

import "core:thread"

import "../ecs"
import "../input"
import "../platform"
import "../renderer"

import mu "vendor:microui"

default_shader_src := #load("../assets/shaders/default.wgsl")
chunk_shader_src := #load("../assets/shaders/chunk.wgsl")

teapot_vox := #load("../assets/objects/teapot.vox")
cactus_vox := #load("../assets/objects/cactus.vox")
test_vox := #load("../assets/objects/test.vox")

GameState :: struct {
	assets:   Assets,
	renderer: ^renderer.Renderer,
	input:    input.InputManager,
	world:    ^ecs.World,
	window:   ^platform.Window,
	palette: Palette,
	thread_pool: ^thread.Pool,
	mu_ctx: ^mu.Context,
	dispatcher: ECSDispatcher,
	frame_stats: FrameStats,

	player_idx: u32,
	last_player_cx: i32,
	last_player_cy: i32,
	last_player_cz: i32,
	day_time: f32,
}

game_init :: proc(r: ^renderer.Renderer, window: ^platform.Window, mu_ctx: ^mu.Context) -> (state: GameState) {
	state.renderer = r
	state.mu_ctx = mu_ctx
	state.window = window
	state.assets = assets_init()
	state.input = input.input_init()
	state.world = ecs.world_init()
	state.palette = palette_init_default()
	state.thread_pool = new(thread.Pool)
	state.day_time = 1

	num_cpus := platform.get_num_cores()
	thread.pool_init(state.thread_pool, context.allocator, num_cpus - 1)
	thread.pool_start(state.thread_pool)

	// assets
	default_material := assets_register_material(
		&state.assets,
		"default",
		renderer.material_create(
			state.renderer,
			string(default_shader_src),
			{state.renderer.h_global_bind_group_layout}
		),
	)
	chunk_material := assets_register_material(
		&state.assets,
		"chunk",
		renderer.material_create(
			state.renderer,
			string(chunk_shader_src),
			{state.renderer.h_global_bind_group_layout}
		),
	)

	vertices, indices := renderer.quad_geometry()
	quad_mesh := assets_register_mesh(
		&state.assets,
		"quad",
		renderer.mesh_create(state.renderer, vertices, indices),
	)
	// assets

	assets_register_voxel_prefab(&state.assets, "tree", vox_model_load(teapot_vox))
	assets_register_voxel_prefab(&state.assets, "cactus", vox_model_load(cactus_vox))
	assets_register_voxel_prefab(&state.assets, "test", vox_model_load(test_vox))
	
	biome_catalog_init(&state)
	game_change_render_distance(&state, 5)
	spawn_player(&state)

	state.dispatcher = ecs_dispatcher_init(20.0)

	ecs_dispatcher_add_tick(&state.dispatcher, system_chunk_spawner)
	ecs_dispatcher_add_tick(&state.dispatcher, system_chunk_generate)
	ecs_dispatcher_add_tick(&state.dispatcher, system_update_sun)

	ecs_dispatcher_add_frame(&state.dispatcher, system_resolve_thread_tasks)
	ecs_dispatcher_add_frame(&state.dispatcher, system_physics)
	ecs_dispatcher_add_frame(&state.dispatcher, system_update_player)

	return state
}

game_update :: proc(state: ^GameState, dt: f32) {
	free_all(context.temp_allocator)

	frame_stats_push(&state.frame_stats, dt)

	ecs_dispatcher_update(&state.dispatcher, state, dt)

	if (input.is_key_just_pressed(&state.input, .P)) {
		state.renderer.use_wireframe = !state.renderer.use_wireframe

		// Pipeline needs to be created again to renderer in wireframe mode
		assets_register_material(
			&state.assets,
			"chunk",
			renderer.material_create(
				state.renderer,
				string(chunk_shader_src),
				{state.renderer.h_global_bind_group_layout}
			),
		)
		assets_register_material(
			&state.assets,
			"default",
			renderer.material_create(
				state.renderer,
				string(default_shader_src),
				{state.renderer.h_global_bind_group_layout}
			),
		)
	}
	if (input.is_key_just_pressed(&state.input, .Escape)) {
		state.window.terminate = true
	}
	if (input.is_key_just_pressed(&state.input, .LeftAlt)) {
		platform.toggle_cursor(state.window)
	}
	if (input.is_key_just_pressed(&state.input, .Equal) && state.world.render_distance < 21) {
		game_change_render_distance(state, state.world.render_distance + 1)
		state.last_player_cx += 1
	}
	if (input.is_key_just_pressed(&state.input, .Minus)) {
		game_change_render_distance(state, state.world.render_distance - 1)
		state.last_player_cx += 1
	}

	input.input_update(&state.input)

	microui_update(state, dt)

	platform.watch_file_update()
}

game_destroy :: proc(state: ^GameState) {
	thread.pool_join(state.thread_pool)
	thread.pool_destroy(state.thread_pool)
	free(state.thread_pool)
	free(state.mu_ctx)

	assets_destroy(&state.assets)
	ecs.world_destroy(state.world)
}
