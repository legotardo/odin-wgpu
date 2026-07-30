package main

import "vendor:wgpu"

import "platform"
import "renderer"

wgpu_initialize :: proc(window: ^platform.Window) {
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
			presentMode = .Fifo,
			alphaMode   = .Opaque,
		}

		wgpu.SurfaceConfigure(state.surface, &state.config)

		queue := wgpu.DeviceGetQueue(device)

		state.renderer = renderer.renderer_init(device, queue, width, height)

		platform.prepare_context(&state.window)
	}
}
