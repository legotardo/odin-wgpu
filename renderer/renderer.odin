package renderer

import "vendor:wgpu"
import "core:math/linalg"

Renderer :: struct {
	device:        wgpu.Device,
	queue:         wgpu.Queue,
	use_wireframe: bool,

	global_bind_group:   wgpu.BindGroup,
	global_layout_group: wgpu.BindGroupLayout,

	palette_buffer: wgpu.Buffer,
	camera_buffer:  wgpu.Buffer,
	light_buffer: wgpu.Buffer,

	depth_texture_view: wgpu.TextureView,
}

RenderItem :: struct {
	mesh:     ^Mesh,
	material: ^Material,
}

renderer_init :: proc(device: wgpu.Device, queue: wgpu.Queue, s_config: ^wgpu.SurfaceConfiguration) -> Renderer {
	camera_buffer := renderer_create_camera_buffer(device)
	palette_buffer := renderer_create_palette_buffer(device)
	light_buffer := renderer_create_light_buffer(device)
	depth_texture_view := renderer_create_depth_texture_view(device, s_config)

	layout_entries := [3]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex},
			buffer = {
				type = .Uniform,
				hasDynamicOffset = false,
				minBindingSize = size_of(linalg.Matrix4f32),
			},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			buffer = {
				type = .ReadOnlyStorage,
				hasDynamicOffset = false,
				minBindingSize = size_of(linalg.Vector4f32) * 256,
			},
		},
		{
			binding = 2,
			visibility = {.Fragment},
			buffer = {
				type = .ReadOnlyStorage,
				hasDynamicOffset = false,
				minBindingSize = size_of(u32) * 4 + size_of(LightData) * 1024,
			},
		},
	}


	global_layout_group := wgpu.DeviceCreateBindGroupLayout(
		device,
		&{
			entries = raw_data(layout_entries[:]),
			entryCount = len(layout_entries),
			label = "global bind group layout",
		},
	)

	group_entries := [3]wgpu.BindGroupEntry {
		{binding = 0, buffer = camera_buffer, size = size_of(linalg.Matrix4f32)},
		{binding = 1, buffer = palette_buffer, size = size_of(linalg.Vector4f32) * 256},
		{binding = 2, buffer = light_buffer, size = size_of(u32) * 4 + size_of(LightData) * 1024},
	}

	global_bind_group := wgpu.DeviceCreateBindGroup(
		device,
		&{
			layout = global_layout_group,
			entries = raw_data(group_entries[:]),
			entryCount = len(group_entries),
			label = "global bind group",
		},
	)

	return {
		device = device,
		queue = queue,
		use_wireframe = false,
		global_bind_group = global_bind_group,
		global_layout_group = global_layout_group,
		camera_buffer = camera_buffer,
		palette_buffer = palette_buffer,
		depth_texture_view = depth_texture_view,
		light_buffer = light_buffer,
	}
}

renderer_draw :: proc(r: ^Renderer, target_view: wgpu.TextureView, items: []RenderItem) {
	encoder := wgpu.DeviceCreateCommandEncoder(r.device, nil)
	defer wgpu.CommandEncoderRelease(encoder)

	render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = target_view,
				loadOp = .Clear,
				storeOp = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = {0.47, 0.68, 0.87, 1},
			},
			depthStencilAttachment = &{
				view = r.depth_texture_view,
				depthLoadOp = .Clear,
				depthStoreOp = .Store,
				depthClearValue = 1.0,
				depthReadOnly = false,
			}
		},
	)

	wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, r.global_bind_group)

	for item in items {
		wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, item.material.pipeline)
		wgpu.RenderPassEncoderSetVertexBuffer(
			render_pass_encoder,
			0,
			item.mesh.vertex_buffer,
			0,
			u64(size_of(Vertex) * item.mesh.vertex_count),
		)
		wgpu.RenderPassEncoderSetIndexBuffer(
			render_pass_encoder,
			item.mesh.index_buffer,
			.Uint16,
			0,
			u64(size_of(u16) * item.mesh.index_count),
		)
		wgpu.RenderPassEncoderDrawIndexed(
			render_pass_encoder,
			indexCount = item.mesh.index_count,
			instanceCount = 1,
			firstIndex = 0,
			baseVertex = 0,
			firstInstance = 0,
		)
	}

	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(r.queue, {command_buffer})
}

renderer_resize :: proc(r: ^Renderer, s_config: ^wgpu.SurfaceConfiguration) {
	r.depth_texture_view = renderer_create_depth_texture_view(r.device, s_config)
}

renderer_destroy :: proc(r: ^Renderer) {
	wgpu.BufferRelease(r.camera_buffer)
	wgpu.BufferRelease(r.palette_buffer)

	wgpu.TextureViewRelease(r.depth_texture_view)

	wgpu.BindGroupRelease(r.global_bind_group)
	wgpu.BindGroupLayoutRelease(r.global_layout_group)

	wgpu.DeviceRelease(r.device)
	wgpu.QueueRelease(r.queue)
}
