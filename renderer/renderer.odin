package renderer

import "vendor:wgpu"
import "core:math/linalg"
import mu "vendor:microui"

import "../platform"
import "../constants"

Renderer :: struct {
	device:        wgpu.Device,
	queue:         wgpu.Queue,
	window: ^platform.Window,
	renderer_manager: RendererManager,
	use_wireframe: bool,

	h_camera_buffer: Handle,

	global_bind_group:   wgpu.BindGroup,
	microui_bind_group:   wgpu.BindGroup,
	lighting_bind_group:     wgpu.BindGroup,
	sun_bind_group:     wgpu.BindGroup,

	global_layout_group: wgpu.BindGroupLayout,
	microui_layout_group: wgpu.BindGroupLayout,
	lighting_layout_group:   wgpu.BindGroupLayout,
	sun_layout_group:   wgpu.BindGroupLayout,

	palette_buffer: wgpu.Buffer,
	render_config_buffer: wgpu.Buffer,
	// light_buffer: wgpu.Buffer,
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

	lighting_pipeline:       wgpu.RenderPipeline,
	lighting_pipeline_layout: wgpu.PipelineLayout,

	shadow_pipeline:       wgpu.RenderPipeline,
	shadow_pipeline_layout: wgpu.PipelineLayout,

	shadow_texture:      wgpu.Texture,
	shadow_texture_view: wgpu.TextureView,
	shadow_sampler:      wgpu.Sampler,
	sun_buffer:          wgpu.Buffer,

	microui_ctx: ^mu.Context,

	total_vertex_count: u64,

	gbuffer: GBuffer,
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
	renderer_manager := renderer_manager_init(device, queue)

	h_camera_buffer := create_buffer(&renderer_manager, &{
		label = "camera buffer",
		usage = {.Uniform, .CopyDst},
		size = size_of(CameraUniform),
	})

	// camera_buffer := renderer_create_camera_buffer(device)
	palette_buffer := renderer_create_palette_buffer(device)
	render_config_buffer := renderer_create_render_config_buffer(device)
	// light_buffer := renderer_create_light_buffer(device)
	instance_buffer := renderer_create_instance_buffer(device)
	microui_constant_buffer := microui_create_constant_buffer(device)
	microui_vertex_buffer := microui_create_vertex_buffer(device)
	microui_texture_buffer := microui_create_tex_buffer(device)
	microui_color_buffer := microui_create_color_buffer(device)
	microui_index_buffer := microui_create_index_buffer(device)

	gbuffer := renderer_create_gbuffer(device, s_config)
	depth_texture_view := renderer_create_depth_texture_view(device, s_config)

	microui_atlas_texture_view, microui_atlas_texture, microui_sampler := microui_create_atlas_texture_view(device)

	shadow_texture, shadow_texture_view, shadow_sampler := renderer_create_shadow_map(device)
	sun_buffer := renderer_create_sun_buffer(device)
	sun_bind_group, sun_layout_group := renderer_create_sun_bind_group(device, sun_buffer)

	// h_global_layout_group := create_bind_group_layout(&renderer_manager, "global layout group", {
	// 	{
	// 		binding = 0,
	// 		visibility = {.Vertex, .Fragment},
	// 		buffer = {
	// 			type = .Uniform,
	// 			hasDynamicOffset = false,
	// 			minBindingSize = size_of(CameraUniform),
	// 		},
	// 	},
	// 	{
	// 		binding = 1,
	// 		visibility = {.Vertex, .Fragment},
	// 		buffer = {
	// 			type = .Uniform,
	// 			hasDynamicOffset = false,
	// 			minBindingSize = size_of(RenderConfigUniform),
	// 		},
	// 	},
	// 	{
	// 		binding = 2,
	// 		visibility = {.Fragment},
	// 		buffer = {
	// 			type = .ReadOnlyStorage,
	// 			hasDynamicOffset = false,
	// 			minBindingSize = size_of(linalg.Vector4f32) * 256,
	// 		},
	// 	},
	// 	{
	// 		binding = 3,
	// 		visibility = {.Vertex},
	// 		buffer = {
	// 			type = .ReadOnlyStorage,
	// 			hasDynamicOffset = false,
	// 			minBindingSize = size_of(linalg.Matrix4f32) * constants.MAX_INSTANCES_COUNT,
	// 		},
	// 	},
	// })
	// h_global_bind_group := create_bind_group(&renderer_manager, "global bind group", h_global_layout_group, {
	// 	{binding = 0, buffer = get_buffer(&renderer_manager, h_camera_buffer), size = size_of(CameraUniform)},
	// 	{binding = 1, buffer = render_config_buffer, size = size_of(RenderConfigUniform)},
	// 	{binding = 2, buffer = palette_buffer, size = size_of(linalg.Vector4f32) * 256},
	// 	{binding = 3, buffer = instance_buffer, size = size_of(linalg.Matrix4f32) * constants.MAX_INSTANCES_COUNT},
	// })

	global_bind_group, global_layout_group := renderer_create_global_bind_group(
		device,
		palette_buffer,
		get_buffer(&renderer_manager, h_camera_buffer),
		// light_buffer,
		instance_buffer,
		render_config_buffer,
	)
	lighting_bind_group, lighting_layout_group := renderer_create_lighting_bind_group(
		device,
		&gbuffer,
		depth_texture_view,
		get_buffer(&renderer_manager, h_camera_buffer), 
		render_config_buffer,
		sun_buffer,
		shadow_texture_view,
		shadow_sampler,
	)
	microui_bind_group, microui_layout_group := microui_create_bind_group(
		device,
		microui_sampler,
		microui_atlas_texture_view,
		microui_constant_buffer,
	)

	microui_pipeline, microui_pipeline_layout := microui_create_pipeline(device, &microui_layout_group)
	shadow_pipeline, shadow_pipeline_layout := renderer_create_shadow_pipeline(
		device,
		global_layout_group,
		sun_layout_group
	)
	lighting_pipeline, lighting_pipeline_layout := renderer_create_lighting_pipeline(device, &lighting_layout_group, s_config)

	microui_update_atlas_texture(queue, microui_atlas_texture)
	microui_update_constant(queue, microui_constant_buffer, window)

	return {
		device = device,
		queue = queue,
		window = window,
		renderer_manager = renderer_manager,
		use_wireframe = false,

		h_camera_buffer = h_camera_buffer,

		global_bind_group = global_bind_group,
		global_layout_group = global_layout_group,
		palette_buffer = palette_buffer,
		depth_texture_view = depth_texture_view,
		// light_buffer = light_buffer,
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

		gbuffer = gbuffer,
		lighting_bind_group = lighting_bind_group,
		lighting_layout_group = lighting_layout_group,
		lighting_pipeline = lighting_pipeline,
		lighting_pipeline_layout = lighting_pipeline_layout,

		shadow_sampler = shadow_sampler,
		shadow_texture = shadow_texture,
		shadow_texture_view = shadow_texture_view,
		sun_buffer = sun_buffer,
		sun_bind_group = sun_bind_group,
		sun_layout_group = sun_layout_group,
		shadow_pipeline = shadow_pipeline,
		shadow_pipeline_layout = shadow_pipeline_layout,
	}
}

renderer_draw :: proc(r: ^Renderer, target_view: wgpu.TextureView, items: []RenderItem) {
	defer delete(items)

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

	encoder := wgpu.DeviceCreateCommandEncoder(r.device, nil)
	defer wgpu.CommandEncoderRelease(encoder)

	shadow_pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&{
			label = "shadow render pass",
			colorAttachmentCount = 0,
			depthStencilAttachment = &{
				view = r.shadow_texture_view,
				depthLoadOp = .Clear,
				depthStoreOp = .Store,
				depthClearValue = 1.0,
				depthReadOnly = false,
			}
		},
	)

	wgpu.RenderPassEncoderSetPipeline(shadow_pass, r.shadow_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(shadow_pass, 0, r.global_bind_group)
	wgpu.RenderPassEncoderSetBindGroup(shadow_pass, 1, r.sun_bind_group)

	for item, i in items {
		wgpu.RenderPassEncoderSetVertexBuffer(
			shadow_pass,
			0,
			item.mesh.vertex_buffer,
			0,
			u64(size_of(Vertex) * item.mesh.vertex_count),
		)
		wgpu.RenderPassEncoderSetIndexBuffer(
			shadow_pass,
			item.mesh.index_buffer,
			.Uint16,
			0,
			u64(size_of(u16) * item.mesh.index_count),
		)
		wgpu.RenderPassEncoderDrawIndexed(
			shadow_pass,
			indexCount = item.mesh.index_count,
			instanceCount = 1,
			firstIndex = 0,
			baseVertex = 0,
			firstInstance = u32(i),
		)
	}

	wgpu.RenderPassEncoderEnd(shadow_pass)
	wgpu.RenderPassEncoderRelease(shadow_pass)

	attachments := [2]wgpu.RenderPassColorAttachment{
		{ 
			view = r.gbuffer.albedo_view,
			loadOp = .Clear,
			storeOp = .Store,
			clearValue = {0.333, 0.721, 1.0, 1.0},
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		},
		{ 
			view = r.gbuffer.normal_view,
			loadOp = .Clear,
			storeOp = .Store,
			clearValue = {0.0, 0.0, 0.0, 0.0},
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		},
	}

	geometry_pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&{
			label = "geometry render pass",
			colorAttachmentCount = len(attachments),
			colorAttachments = raw_data(attachments[:]),
			depthStencilAttachment = &{
				view = r.depth_texture_view,
				depthLoadOp = .Clear,
				depthStoreOp = .Store,
				depthClearValue = 1.0,
				depthReadOnly = false,
			}
		},
	)

	renderer_draw_game(r, geometry_pass, items)
	
	wgpu.RenderPassEncoderEnd(geometry_pass)
	wgpu.RenderPassEncoderRelease(geometry_pass)

	lighting_attachment := wgpu.RenderPassColorAttachment{
		view = target_view,
		loadOp = .Clear,
		storeOp = .Store,
		clearValue = {0.0, 0.0, 0.0, 1.0},
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
	}

	lighting_pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&{
			label = "lighting and ui render pass",
			colorAttachmentCount = 1,
			colorAttachments = &lighting_attachment,
		},
	)

	wgpu.RenderPassEncoderSetPipeline(lighting_pass, r.lighting_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(lighting_pass, 0, r.lighting_bind_group)
	wgpu.RenderPassEncoderDraw(lighting_pass, 3, 1, 0, 0)

	renderer_draw_microui(r, lighting_pass)
	
	wgpu.RenderPassEncoderEnd(lighting_pass)
	wgpu.RenderPassEncoderRelease(lighting_pass)

	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(r.queue, {command_buffer})
}

@(private="file")
renderer_draw_game :: proc(r: ^Renderer, encoder: wgpu.RenderPassEncoder, items: []RenderItem) {


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
	wgpu.TextureViewRelease(r.depth_texture_view)
	renderer_destroy_gbuffer(&r.gbuffer)
	wgpu.BindGroupRelease(r.lighting_bind_group)

	r.depth_texture_view = renderer_create_depth_texture_view(r.device, s_config)
	r.gbuffer = renderer_create_gbuffer(r.device, s_config)

	r.lighting_bind_group, _ = renderer_create_lighting_bind_group(
		r.device,
		&r.gbuffer,
		r.depth_texture_view,
		get_buffer(&r.renderer_manager, r.h_camera_buffer),
		r.render_config_buffer,
		r.sun_buffer,
		r.shadow_texture_view,
		r.shadow_sampler,
	)

	microui_update_constant(r.queue, r.microui_constant_buffer, r.window)
}

renderer_destroy :: proc(r: ^Renderer) {
	renderer_manager_destroy(&r.renderer_manager)

	// wgpu.BufferRelease(r.camera_buffer)
	wgpu.BufferRelease(r.palette_buffer)
	// wgpu.BufferRelease(r.light_buffer)
	wgpu.BufferRelease(r.instance_buffer)
	wgpu.BufferRelease(r.microui_constant_buffer)
	wgpu.BufferRelease(r.microui_texture_buffer)
	wgpu.BufferRelease(r.microui_texture_buffer)
	wgpu.BufferRelease(r.microui_color_buffer)
	wgpu.BufferRelease(r.microui_index_buffer)
	wgpu.BufferRelease(r.render_config_buffer)
	wgpu.BufferRelease(r.sun_buffer)

	wgpu.TextureViewRelease(r.depth_texture_view)
	wgpu.TextureViewRelease(r.microui_atlas_texture_view)
	wgpu.TextureViewRelease(r.shadow_texture_view)

	wgpu.BindGroupRelease(r.global_bind_group)
	wgpu.BindGroupRelease(r.microui_bind_group)
	wgpu.BindGroupRelease(r.lighting_bind_group)
	wgpu.BindGroupRelease(r.sun_bind_group)
	wgpu.BindGroupLayoutRelease(r.global_layout_group)
	wgpu.BindGroupLayoutRelease(r.microui_layout_group)
	wgpu.BindGroupLayoutRelease(r.lighting_layout_group)
	wgpu.BindGroupLayoutRelease(r.sun_layout_group)

	wgpu.SamplerRelease(r.microui_sampler)
	wgpu.SamplerRelease(r.shadow_sampler)

	renderer_destroy_gbuffer(&r.gbuffer)

	wgpu.RenderPipelineRelease(r.microui_pipeline)
	wgpu.PipelineLayoutRelease(r.microui_pipeline_layout)

	wgpu.RenderPipelineRelease(r.lighting_pipeline)
	wgpu.PipelineLayoutRelease(r.lighting_pipeline_layout)

	wgpu.RenderPipelineRelease(r.shadow_pipeline)
	wgpu.PipelineLayoutRelease(r.shadow_pipeline_layout)

	wgpu.TextureRelease(r.microui_atlas_texture)
	wgpu.TextureRelease(r.shadow_texture)

	wgpu.DeviceRelease(r.device)

	wgpu.QueueRelease(r.queue)
}
