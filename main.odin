package main

import "base:runtime"
import "core:fmt"
import "vendor:wgpu"

import platform "platform"

default_shader_src := #load("assets/shaders/minimal.wgsl")

state: struct {
	ctx:             runtime.Context,
	window:          platform.Window,
	instance:        wgpu.Instance,
	surface:         wgpu.Surface,
	adapter:         wgpu.Adapter,
	device:          wgpu.Device,
	config:          wgpu.SurfaceConfiguration,
	queue:           wgpu.Queue,
	pipeline:        wgpu.RenderPipeline,
	pipeline_layout: wgpu.PipelineLayout,
	shader_module:   wgpu.ShaderModule,
}

main :: proc() {
	// Caution to use defer here, because web don't lock this function til finish
	state.window = platform.create_window()

	state.window.resize_callback = resize

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

		state.device = device

		width, height := platform.get_frame_size(&state.window)
		fmt.printf("W = %d H = %d", width, height)
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

		state.queue = wgpu.DeviceGetQueue(state.device)

		state.shader_module = wgpu.DeviceCreateShaderModule(
			state.device,
			&{
				nextInChain = &wgpu.ShaderSourceWGSL {
					sType = .ShaderSourceWGSL,
					code = string(default_shader_src),
				},
			},
		)
		state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(state.device, &{})
		state.pipeline = wgpu.DeviceCreateRenderPipeline(
			state.device,
			&{
				layout = state.pipeline_layout,
				vertex = {module = state.shader_module, entryPoint = "vs_main"},
				fragment = &{
					module = state.shader_module,
					entryPoint = "fs_main",
					targetCount = 1,
					targets = &wgpu.ColorTargetState {
						format = .BGRA8Unorm,
						writeMask = wgpu.ColorWriteMaskFlags_All,
					},
				},
				primitive = {topology = .TriangleList},
				multisample = {count = 1, mask = 0xFFFFFFFF},
			},
		)

		platform.prepare_context(&state.window)
	}

	platform.run(&state.window, update, finish)
}

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

	encoder := wgpu.DeviceCreateCommandEncoder(state.device, nil)
	defer wgpu.CommandEncoderRelease(encoder)

	render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = view,
				loadOp = .Clear,
				storeOp = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = {0.47, 0.68, 0.87, 1},
			},
		},
	)

	wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, state.pipeline)
	wgpu.RenderPassEncoderDraw(
		render_pass_encoder,
		vertexCount = 3,
		instanceCount = 1,
		firstVertex = 0,
		firstInstance = 0,
	)

	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(state.queue, {command_buffer})
	wgpu.SurfacePresent(state.surface)
}

resize :: proc(width, height: u32) {
	context = state.ctx

	state.config.width, state.config.height = platform.get_frame_size(&state.window)
	wgpu.SurfaceConfigure(state.surface, &state.config)
}

finish :: proc() {
	wgpu.RenderPipelineRelease(state.pipeline)
	wgpu.PipelineLayoutRelease(state.pipeline_layout)
	wgpu.ShaderModuleRelease(state.shader_module)
	wgpu.QueueRelease(state.queue)
	wgpu.DeviceRelease(state.device)
	wgpu.AdapterRelease(state.adapter)
	wgpu.SurfaceRelease(state.surface)
	wgpu.InstanceRelease(state.instance)
	platform.destroy_window(&state.window)
}
