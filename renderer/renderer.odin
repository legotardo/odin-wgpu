package renderer

import "vendor:wgpu"
import "core:math/linalg"
import mu "vendor:microui"

import "../platform"

Renderer :: struct {
	device:        wgpu.Device,
	queue:         wgpu.Queue,
	window: ^platform.Window,
	use_wireframe: bool,

	global_bind_group:   wgpu.BindGroup,
	microui_bind_group:   wgpu.BindGroup,

	global_layout_group: wgpu.BindGroupLayout,
	microui_layout_group: wgpu.BindGroupLayout,

	palette_buffer: wgpu.Buffer,
	camera_buffer:  wgpu.Buffer,
	render_config_buffer: wgpu.Buffer,
	light_buffer: wgpu.Buffer,
	instance_buffer: wgpu.Buffer,
	microui_constant_buffer: wgpu.Buffer,
	microui_vertex_buffer: wgpu.Buffer,
	microui_texture_buffer: wgpu.Buffer,
	microui_color_buffer: wgpu.Buffer,
	microui_index_buffer: wgpu.Buffer,

	depth_texture_view: wgpu.TextureView,
	microui_atlas_texture_view: wgpu.TextureView,

	microui_sampler: wgpu.Sampler,

	microui_atlas_texture: wgpu.Texture,

	microui_pipeline: wgpu.RenderPipeline,
	microui_pipeline_layout: wgpu.PipelineLayout,

	microui_ctx: ^mu.Context,

	total_vertex_count: u64,
}

RenderItem :: struct {
	mesh:     ^Mesh,
	material: ^Material,
	transform: linalg.Matrix4f32,
	should_use_instance: bool
}

renderer_init :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	s_config: ^wgpu.SurfaceConfiguration,
	window: ^platform.Window,
	microui_ctx: ^mu.Context
) -> Renderer {
	camera_buffer := renderer_create_camera_buffer(device)
	palette_buffer := renderer_create_palette_buffer(device)
	render_config_buffer := renderer_create_render_config_buffer(device)
	light_buffer := renderer_create_light_buffer(device)
	instance_buffer := renderer_create_instance_buffer(device)
	microui_constant_buffer := microui_create_constant_buffer(device)
	microui_vertex_buffer := microui_create_vertex_buffer(device)
	microui_texture_buffer := microui_create_tex_buffer(device)
	microui_color_buffer := microui_create_color_buffer(device)
	microui_index_buffer := microui_create_index_buffer(device)

	depth_texture_view := renderer_create_depth_texture_view(device, s_config)
	microui_atlas_texture_view, microui_atlas_texture, microui_sampler := microui_create_atlas_texture_view(device)

	global_bind_group, global_layout_group := renderer_create_global_bind_group(
		device,
		palette_buffer,
		camera_buffer,
		light_buffer,
		instance_buffer,
		render_config_buffer,
	)
	microui_bind_group, microui_layout_group := microui_create_bind_group(
		device,
		microui_sampler,
		microui_atlas_texture_view,
		microui_constant_buffer,
	)

	microui_pipeline, microui_pipeline_layout := microui_create_pipeline(device, &microui_layout_group)

	microui_update_atlas_texture(queue, microui_atlas_texture)
	microui_update_constant(queue, microui_constant_buffer, window)

	return {
		device = device,
		queue = queue,
		window = window,
		use_wireframe = false,
		global_bind_group = global_bind_group,
		global_layout_group = global_layout_group,
		camera_buffer = camera_buffer,
		palette_buffer = palette_buffer,
		depth_texture_view = depth_texture_view,
		light_buffer = light_buffer,
		instance_buffer = instance_buffer,
		render_config_buffer = render_config_buffer,

		microui_vertex_buffer = microui_vertex_buffer,
		microui_texture_buffer = microui_texture_buffer,
		microui_color_buffer = microui_color_buffer,
		microui_index_buffer = microui_index_buffer,
		microui_constant_buffer = microui_constant_buffer,
		microui_atlas_texture_view = microui_atlas_texture_view,
		microui_sampler = microui_sampler,
		microui_bind_group = microui_bind_group,
		microui_layout_group = microui_layout_group,
		microui_pipeline = microui_pipeline,
		microui_pipeline_layout = microui_pipeline_layout,
		microui_atlas_texture = microui_atlas_texture,
		microui_ctx = microui_ctx,
	}
}

renderer_draw :: proc(r: ^Renderer, target_view: wgpu.TextureView, items: []RenderItem) {
	defer delete(items)

	encoder := wgpu.DeviceCreateCommandEncoder(r.device, nil)
	defer wgpu.CommandEncoderRelease(encoder)

	render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&{
			label = "game render encoder",
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = target_view,
				loadOp = .Clear,
				storeOp = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = {0.333, 0.721, 1.0, 1},
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

	renderer_draw_game(r, render_pass_encoder, items)
	renderer_draw_microui(r, render_pass_encoder)
	
	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(r.queue, {command_buffer})
}

@(private="file")
renderer_draw_game :: proc(r: ^Renderer, encoder: wgpu.RenderPassEncoder, items: []RenderItem) {
	need_instancing := false
	for item in items {
		if item.should_use_instance {
			need_instancing = true
			break
		}
	}
	if need_instancing {
		transforms := renderer_get_instancing_items(items)
		renderer_update_instance_buffer(r, transforms)
		delete(transforms)
	}

	wgpu.RenderPassEncoderSetBindGroup(encoder, 0, r.global_bind_group)

	prev_pipeline: wgpu.RenderPipeline
	for item, i in items {
		if item.material.pipeline != prev_pipeline {
			wgpu.RenderPassEncoderSetPipeline(encoder, item.material.pipeline)
			prev_pipeline = item.material.pipeline
		}
		wgpu.RenderPassEncoderSetVertexBuffer(
			encoder,
			0,
			item.mesh.vertex_buffer,
			0,
			u64(size_of(Vertex) * item.mesh.vertex_count),
		)
		wgpu.RenderPassEncoderSetIndexBuffer(
			encoder,
			item.mesh.index_buffer,
			.Uint16,
			0,
			u64(size_of(u16) * item.mesh.index_count),
		)
		wgpu.RenderPassEncoderDrawIndexed(
			encoder,
			indexCount = item.mesh.index_count,
			instanceCount = 1,
			firstIndex = 0,
			baseVertex = 0,
			firstInstance = u32(i),
		)
	}
}

@(private="file")
renderer_draw_microui :: proc(r: ^Renderer, encoder: wgpu.RenderPassEncoder) {
	wgpu.RenderPassEncoderSetPipeline(encoder, r.microui_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(encoder, 0, r.microui_bind_group)
	wgpu.RenderPassEncoderSetVertexBuffer(encoder, 0, r.microui_vertex_buffer, 0, size_of(microui_state.vert_buf))
	wgpu.RenderPassEncoderSetVertexBuffer(encoder, 1, r.microui_texture_buffer, 0, size_of(microui_state.tex_buf))
	wgpu.RenderPassEncoderSetVertexBuffer(encoder, 2, r.microui_color_buffer, 0, size_of(microui_state.color_buf))
	wgpu.RenderPassEncoderSetIndexBuffer(encoder, r.microui_index_buffer, .Uint32, 0, size_of(microui_state.index_buf))

	microui_render(encoder, r.window, r.microui_ctx)

	wgpu.QueueWriteBuffer(r.queue, r.microui_vertex_buffer, 0, &microui_state.vert_buf, uint(microui_state.buf_idx*8*size_of(f32)))
	wgpu.QueueWriteBuffer(r.queue, r.microui_texture_buffer, 0, &microui_state.tex_buf, uint(microui_state.buf_idx*8*size_of(f32)))
	wgpu.QueueWriteBuffer(r.queue, r.microui_color_buffer, 0, &microui_state.color_buf, uint(microui_state.buf_idx*16))
	wgpu.QueueWriteBuffer(r.queue, r.microui_index_buffer, 0, &microui_state.index_buf, uint(microui_state.buf_idx*6*size_of(u32)))

	if microui_state.buf_idx == 0 { return }
	wgpu.RenderPassEncoderDrawIndexed(encoder, u32(microui_state.buf_idx * 6), 1, 0, 0, 0)

	microui_state.buf_idx = 0
}

renderer_resize :: proc(r: ^Renderer, s_config: ^wgpu.SurfaceConfiguration) {
	r.depth_texture_view = renderer_create_depth_texture_view(r.device, s_config)

	microui_update_constant(r.queue, r.microui_constant_buffer, r.window)
}

renderer_destroy :: proc(r: ^Renderer) {
	wgpu.BufferRelease(r.camera_buffer)
	wgpu.BufferRelease(r.palette_buffer)
	wgpu.BufferRelease(r.light_buffer)
	wgpu.BufferRelease(r.instance_buffer)
	wgpu.BufferRelease(r.microui_constant_buffer)
	wgpu.BufferRelease(r.microui_texture_buffer)
	wgpu.BufferRelease(r.microui_texture_buffer)
	wgpu.BufferRelease(r.microui_color_buffer)
	wgpu.BufferRelease(r.microui_index_buffer)
	wgpu.BufferRelease(r.render_config_buffer)

	wgpu.TextureViewRelease(r.depth_texture_view)
	wgpu.TextureViewRelease(r.microui_atlas_texture_view)

	wgpu.BindGroupRelease(r.global_bind_group)
	wgpu.BindGroupRelease(r.microui_bind_group)
	wgpu.BindGroupLayoutRelease(r.global_layout_group)
	wgpu.BindGroupLayoutRelease(r.microui_layout_group)

	wgpu.SamplerRelease(r.microui_sampler)

	wgpu.RenderPipelineRelease(r.microui_pipeline)
	wgpu.PipelineLayoutRelease(r.microui_pipeline_layout)

	wgpu.TextureRelease(r.microui_atlas_texture)

	wgpu.DeviceRelease(r.device)

	wgpu.QueueRelease(r.queue)
}
