package main

import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import "vendor:wgpu"

import "game"
import "platform"

default_shader_src := #load("assets/shaders/minimal.wgsl")

state: struct {
	ctx:               runtime.Context,
	window:            platform.Window,
	instance:          wgpu.Instance,
	surface:           wgpu.Surface,
	adapter:           wgpu.Adapter,
	device:            wgpu.Device,
	config:            wgpu.SurfaceConfiguration,
	queue:             wgpu.Queue,
	render_pipeline:   wgpu.RenderPipeline,
	pipeline_layout:   wgpu.PipelineLayout,
	shader_module:     wgpu.ShaderModule,
	vertex_buffer:     wgpu.Buffer,
	index_buffer:      wgpu.Buffer,
	camera:            game.Camera,
	camera_buffer:     wgpu.Buffer,
	camera_bind_group: wgpu.BindGroup,
}

main :: proc() {
	// Caution to use defer here, because web don't lock this function til finish
	state.window = platform.create_window()
	state.camera = game.camera_new(state.window.width, state.window.height)

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


		state.vertex_buffer = wgpu.DeviceCreateBufferWithDataSlice(
			state.device,
			&{label = "vertex buffer", usage = {.Vertex}},
			game.sample_vertex[:],
		)
		state.index_buffer = wgpu.DeviceCreateBufferWithDataSlice(
			state.device,
			&{label = "index buffer", usage = {.Index}},
			game.sample_indices[:],
		)
		state.camera_buffer = wgpu.DeviceCreateBufferWithDataTyped(
			state.device,
			&{label = "camera buffer", usage = {.Uniform, .CopyDst}},
			game.camera_build_matrix(&state.camera),
		)


		layout_entries := [1]wgpu.BindGroupLayoutEntry {
			{
				binding = 0,
				visibility = {.Vertex},
				buffer = {
					type = .Uniform,
					hasDynamicOffset = false,
					minBindingSize = size_of(linalg.Matrix4f32),
				},
			},
		}
		camera_bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
			state.device,
			&{
				entries = raw_data(layout_entries[:]),
				entryCount = len(layout_entries),
				label = "camera bind group layout",
			},
		)

		bind_group_entries := [1]wgpu.BindGroupEntry {
			{binding = 0, buffer = state.camera_buffer, size = size_of(linalg.Matrix4f32)},
		}
		state.camera_bind_group = wgpu.DeviceCreateBindGroup(
			state.device,
			&{
				layout = camera_bind_group_layout,
				entries = raw_data(bind_group_entries[:]),
				entryCount = len(bind_group_entries),
				label = "camera bind group",
			},
		)

		bind_group_layouts := [1]wgpu.BindGroupLayout{camera_bind_group_layout}
		state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
			state.device,
			&{
				bindGroupLayouts = raw_data(bind_group_layouts[:]),
				bindGroupLayoutCount = 1,
				immediateSize = 0,
			},
		)

		state.render_pipeline = wgpu.DeviceCreateRenderPipeline(
			state.device,
			&{
				layout = state.pipeline_layout,
				vertex = {
					module = state.shader_module,
					entryPoint = "vs_main",
					buffers = raw_data(
						[]wgpu.VertexBufferLayout{game.vertex_to_wgpu(game.sample_vertex[:])},
					),
					bufferCount = 1,
				},
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

	wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, state.render_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, state.camera_bind_group, {})

	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass_encoder,
		0,
		state.vertex_buffer,
		0,
		u64(size_of(game.Vertex) * len(game.sample_vertex)),
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		render_pass_encoder,
		state.index_buffer,
		.Uint16,
		0,
		u64(size_of(u16) * len(game.sample_indices)),
	)
	wgpu.RenderPassEncoderDrawIndexed(
		render_pass_encoder,
		indexCount = len(game.sample_indices),
		instanceCount = 1,
		firstIndex = 0,
		baseVertex = 0,
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

	if state.camera_buffer != nil {
		state.camera.aspect = f32(state.config.width) / f32(state.config.height)
		mat := game.camera_build_matrix(&state.camera)
		wgpu.QueueWriteBuffer(state.queue, state.camera_buffer, 0, &mat, size_of(mat))
	}
}

finish :: proc() {
	wgpu.RenderPipelineRelease(state.render_pipeline)
	wgpu.PipelineLayoutRelease(state.pipeline_layout)
	wgpu.ShaderModuleRelease(state.shader_module)
	wgpu.QueueRelease(state.queue)
	wgpu.DeviceRelease(state.device)
	wgpu.AdapterRelease(state.adapter)
	wgpu.SurfaceRelease(state.surface)
	wgpu.InstanceRelease(state.instance)
	wgpu.BufferRelease(state.vertex_buffer)

	platform.destroy_window(&state.window)
}
