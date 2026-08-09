package main

import "core:math/linalg"
import "core:fmt"
import "vendor:wgpu"

import "game"
import "input"
import "platform"
import "renderer"

wgpu_init :: proc(window: ^platform.Window) {
	state.window.resize_callback = resize
	state.window.key_callback = key_callback
	state.window.cursor_callback = cursor_callback

	state.instance = wgpu.CreateInstance(nil)
	assert(state.instance != nil, "WGPU Failed to create a new instance")

	state.surface = platform.get_window_surface(&state.window, state.instance)
	assert(state.surface != nil, "WGPU Failed to create a new surface")

	wgpu.InstanceRequestAdapter(
		state.instance,
		&{compatibleSurface = state.surface},
		{callback = on_adapter},
	)

	on_adapter :: proc "c" (
		status: wgpu.RequestAdapterStatus,
		adapter: wgpu.Adapter,
		message: string,
		userdata1: rawptr,
		userdata2: rawptr,
	) {
		context = state.ctx
		assert(status == .Success, "Failed to request adapter")

		if (ODIN_ARCH == .wasm64p32 || ODIN_ARCH == .wasm32) {
			state.adapter = adapter

			wgpu.AdapterRequestDevice(
				adapter,
				&{requiredFeatureCount = 0},
				{callback = on_device},
			)
		} else {
			state.adapter = adapter
			features := [2]wgpu.FeatureName{.PolygonModeLine, .VertexWritableStorage}

			wgpu.AdapterRequestDevice(
				adapter,
				&{requiredFeatures = raw_data(features[:]), requiredFeatureCount = len(features)},
				{callback = on_device},
			)
		}
	}

	on_device :: proc "c" (
		status: wgpu.RequestDeviceStatus,
		device: wgpu.Device,
		message: string,
		userdata1: rawptr,
		userdata2: rawptr,
	) {
		context = state.ctx
		assert(status == .Success, "Failed to request adapter device")

		width, height := platform.get_frame_size(&state.window)
		state.config = wgpu.SurfaceConfiguration {
			width       = width,
			height      = height,
			device      = device,
			usage       = {.RenderAttachment},
			format      = .BGRA8Unorm,
			presentMode = .Immediate, //Timing of display
			alphaMode   = .Opaque,
		}

		wgpu.SurfaceConfigure(state.surface, &state.config)

		queue := wgpu.DeviceGetQueue(device)

		mu_ctx := game.microui_init()

		state.renderer = renderer.renderer_init(device, queue, &state.config, &state.window, mu_ctx)
		state.game_state = game.game_init(&state.renderer, &state.window, mu_ctx)
		renderer.write_buffer_2(&state.renderer.renderer_manager, state.renderer.h_palette_buffer, &state.game_state.palette.colors)

		platform.prepare_context(&state.window)
	}

	platform.run(&state.window, update, finish)
}

@(private = "file")
update :: proc(dt: f32) {
	context = state.ctx

	assert(state.surface != nil, "WGPU Failed to create a new surface")
	surface_texture := wgpu.SurfaceGetCurrentTexture(state.surface)
	switch surface_texture.status {
	case .SuccessOptimal, .SuccessSuboptimal:
	// All good
	case .Timeout, .Outdated, .Lost:
		// Skiped
		if surface_texture.texture != nil {
			wgpu.TextureRelease(surface_texture.texture)
		}

		resize(state.window.width, state.window.height)
		return
	case .Occluded:
		return
	case .Error:
		fmt.panicf("Failed to get current texture with status %v", surface_texture.status)
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	view := wgpu.TextureCreateView(surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(view)

	game.game_update(&state.game_state, dt)

	cam_matrix := game.game_get_camera_matrix(&state.game_state)
	cam_pos := game.game_get_camera_eye(&state.game_state)
	renderer.write_buffer_2(&state.renderer.renderer_manager, state.renderer.h_camera_buffer, &renderer.CameraUniform{ 
		view_proj = cam_matrix,
		view_proj_inv = linalg.matrix4_inverse(cam_matrix),
		position = cam_pos
	})
	sun_uniform := game.game_calculate_sun(&state.game_state, cam_pos)
	renderer.write_buffer_2(&state.renderer.renderer_manager, state.renderer.h_sun_buffer, &sun_uniform)

	game_items_to_draw := game.game_get_render_items(&state.game_state)
	renderer.renderer_draw(&state.renderer, view, game_items_to_draw)

	wgpu.SurfacePresent(state.surface)
}

@(private = "file")
resize :: proc(width, height: u32) {
	if (width <= 0 || height <= 0) do return

	context = state.ctx

	state.config.width, state.config.height = platform.get_frame_size(&state.window)
	wgpu.SurfaceConfigure(state.surface, &state.config)

	game.game_update_camera_component(&state.game_state, state.config.width, state.config.height)

	renderer.renderer_resize(&state.renderer, &state.config)
}

@(private = "file")
key_callback :: proc(key: input.Key, down: bool) {
	input.input_set_key_state(&state.game_state.input, key, down)
}

@(private = "file")
cursor_callback :: proc(x, y: f32) {
	input.input_set_mouse_position(&state.game_state.input, x, y)
}

@(private = "file")
finish :: proc() {
	context = state.ctx

	game.game_destroy(&state.game_state)

	renderer.renderer_destroy(&state.renderer)

	wgpu.AdapterRelease(state.adapter)
	wgpu.SurfaceRelease(state.surface)
	wgpu.InstanceRelease(state.instance)

	platform.destroy_window(&state.window)
}
