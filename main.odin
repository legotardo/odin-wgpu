package main

import "base:runtime"
import "core:fmt"
import "vendor:wgpu"

import "game"
import "platform"
import "renderer"


state: struct {
	ctx:      runtime.Context,
	window:   platform.Window,
	instance: wgpu.Instance,
	surface:  wgpu.Surface,
	adapter:  wgpu.Adapter,
	config:   wgpu.SurfaceConfiguration,
	renderer: renderer.Renderer,
}

main :: proc() {
	// Caution to use defer here, because web don't lock this function til finish
	state.window = platform.create_window()
	state.window.resize_callback = resize

	wgpu_initialize(&state.window)

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
		// Minimized
		return
	case .Error:
		fmt.panicf("Failed to get current texture with status %v", surface_texture.status)
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	view := wgpu.TextureCreateView(surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(view)

	renderer.renderer_draw(&state.renderer, view)

	wgpu.SurfacePresent(state.surface)
}

@(private = "file")
resize :: proc(width, height: u32) {
	context = state.ctx

	state.config.width, state.config.height = platform.get_frame_size(&state.window)
	wgpu.SurfaceConfigure(state.surface, &state.config)

	// if state.camera_buffer != nil {
	// 	state.camera.aspect = f32(state.config.width) / f32(state.config.height)
	// 	mat := game.camera_build_matrix(&state.camera)
	// 	wgpu.QueueWriteBuffer(state.queue, state.camera_buffer, 0, &mat, size_of(mat))
	// }
}
@(private = "file")
finish :: proc() {
	renderer.renderer_destroy(&state.renderer)

	wgpu.AdapterRelease(state.adapter)
	wgpu.SurfaceRelease(state.surface)
	wgpu.InstanceRelease(state.instance)

	platform.destroy_window(&state.window)
}
