package main

import "core:fmt"
import "vendor:wgpu"

import "game"
import "input"
import "platform"
import "renderer"

wgpu_initialize :: proc(window: ^platform.Window) {
	state.window.resize_callback = resize
	state.window.key_callback = key_callback

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

		state.adapter = adapter
		wgpu.AdapterRequestDevice(adapter, nil, {callback = on_device})
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
			presentMode = .Fifo, //Timing of display
			alphaMode   = .Opaque,
		}

		wgpu.SurfaceConfigure(state.surface, &state.config)

		queue := wgpu.DeviceGetQueue(device)

		state.renderer = renderer.renderer_init(device, queue, width, height)
		state.game_state = game.game_init(&state.renderer)

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

	game_items_to_draw := game.game_get_render_items(&state.game_state)
	renderer.renderer_draw(&state.renderer, view, game_items_to_draw)

	wgpu.SurfacePresent(state.surface)
}

@(private = "file")
resize :: proc(width, height: u32) {
	context = state.ctx

	state.config.width, state.config.height = platform.get_frame_size(&state.window)
	wgpu.SurfaceConfigure(state.surface, &state.config)

	if state.renderer.camera.buffer != nil {
		state.renderer.camera.data.aspect = f32(state.config.width) / f32(state.config.height)
		mat := renderer.camera_build_matrix(&state.renderer.camera.data)
		wgpu.QueueWriteBuffer(
			state.renderer.queue,
			state.renderer.camera.buffer,
			0,
			&mat,
			size_of(mat),
		)
	}
}

@(private = "file")
key_callback :: proc(key: input.Key, down: bool) {
	input.input_set_key_state(&state.game_state.input, key, down)
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
