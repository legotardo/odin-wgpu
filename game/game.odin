package game

import "core:fmt"
import "core:math/linalg"
import "vendor:wgpu"

import "../ecs"
import "../input"
import "../platform"
import "../renderer"

default_shader_src := #load("../assets/shaders/minimal.wgsl")

GameState :: struct {
	assets:   Assets,
	renderer: ^renderer.Renderer,
	input:    input.InputManager,
	world:    ^ecs.World,
	window:   ^platform.Window,
}

game_init :: proc(r: ^renderer.Renderer, window: ^platform.Window) -> GameState {
	assets := assets_init()
	input := input.input_init()

	world := ecs.world_init()


	return {assets = assets, renderer = r, world = world, input = input, window = window}
}

game_awake :: proc(state: ^GameState) {
	// assets
	minimal_material := assets_register_material(
		&state.assets,
		"minimal",
		renderer.material_create(
		state.renderer,
		string(default_shader_src),
		renderer.vertex_get_buffer_layout(),
		// TODO: Maybe we can move this bind thing to another place
		// because the camera.bind_group it's used in render_draw call
		// it's anoying to have this data in different places
		[]wgpu.BindGroupLayout{state.renderer.camera.bind_group_layout},
		),
	)

	vertices, indices := renderer.quad_geometry()
	quad_mesh := assets_register_mesh(
		&state.assets,
		"quad",
		renderer.mesh_create(state.renderer, vertices, indices),
	)
	// assets

	width, height := platform.get_frame_size(state.window)
	camera := ecs.entity_create(state.world)
	ecs.entity_add_transform(state.world, camera, {position = {0, 0, 2}, scale = {1, 1, 1}})
	ecs.entity_add_first_person(
		state.world,
		camera,
		{sensitivity = 0.1, pitch = 0, yaw = 0, speed = 3},
	)
	ecs.entity_add_camera(
		state.world,
		camera,
		{
			target = {0, 0, 0},
			up = {0, 1, 0},
			aspect = f32(width) / f32(height),
			fovy = 90 * linalg.RAD_PER_DEG,
			zfar = 100,
			znear = 0.1,
		},
	)

	quad := ecs.entity_create(state.world)
	ecs.entity_add_transform(state.world, quad, {})
	ecs.entity_add_render(
		state.world,
		quad,
		{mesh = string(quad_mesh), material = string(minimal_material)},
	)

	chunk := ecs.entity_create(state.world)
	ecs.entity_add_transform(state.world, chunk, {})
	ecs.entity_add_chunk(state.world, chunk, {})
}

game_update :: proc(state: ^GameState, dt: f32) {
	// fmt.printf("%f FPS\n", 1 / dt)

	system_update_camera(state, dt)
	system_generate_chunk(state)
	system_generate_chunk_mesh(state)

	if (input.is_key_just_pressed(&state.input, .P)) {
		state.renderer.use_wireframe = !state.renderer.use_wireframe

		// Pipeline needs to be created again to renderer in wireframe mode
		assets_register_material(
			&state.assets,
			"minimal",
			renderer.material_create(
				state.renderer,
				string(default_shader_src),
				renderer.vertex_get_buffer_layout(),
				[]wgpu.BindGroupLayout{state.renderer.camera.bind_group_layout},
			),
		)
	}
	if (input.is_key_just_pressed(&state.input, .Escape)) {
		state.window.terminate = true
	}

	input.input_update(&state.input)
}

game_destroy :: proc(state: ^GameState) {
	assets_destroy(&state.assets)
}
