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
	h_palette_buffer: Handle,
	h_render_config_buffer: Handle,
	h_instance_buffer: Handle,
	h_global_bind_group: Handle,
	h_global_bind_group_layout: Handle,
	h_microui_constant_buffer: Handle,
	h_microui_vertex_buffer: Handle,
	h_microui_texture_buffer: Handle,
	h_microui_color_buffer: Handle,
	h_microui_index_buffer: Handle,
	h_sun_buffer: Handle,
	h_sun_bind_group: Handle,
	h_sun_bind_group_layout: Handle,

	microui_bind_group:   wgpu.BindGroup,
	lighting_bind_group:     wgpu.BindGroup,
	// sun_bind_group:     wgpu.BindGroup,

	microui_layout_group: wgpu.BindGroupLayout,
	lighting_layout_group:   wgpu.BindGroupLayout,
	// sun_layout_group:   wgpu.BindGroupLayout,


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
	h_palette_buffer := create_buffer(&renderer_manager, &{
		label = "palette buffer",
		usage = {.Storage, .CopyDst},
		size = size_of(linalg.Vector4f32) * 256,
	})
	h_render_config_buffer := create_buffer(&renderer_manager, &{
		label = "render config buffer",
		usage = {.Uniform, .CopyDst},
		size = size_of(RenderConfigUniform),
	})
	h_instance_buffer := create_buffer(&renderer_manager, &{
		label = "instance buffer",
		usage = {.Storage, .CopyDst},
		size = size_of(linalg.Matrix4f32) * constants.MAX_INSTANCES_COUNT,
	})
	h_microui_constant_buffer := create_buffer(&renderer_manager, &{
		label = "microui constant buffer",
		usage = {.Uniform, .CopyDst},
		size = size_of(linalg.Matrix4f32),
	})
	h_microui_vertex_buffer := create_buffer(&renderer_manager, &{
		label = "microui vertex buffer",
		usage = {.Vertex, .CopyDst},
		size = size_of(microui_state.vert_buf),
	})
	h_microui_texture_buffer := create_buffer(&renderer_manager, &{
		label = "microui texture buffer",
		usage = {.Vertex, .CopyDst},
		size = size_of(microui_state.tex_buf),
	})
	h_microui_color_buffer := create_buffer(&renderer_manager, &{
		label = "microui color buffer",
		usage = {.Vertex, .CopyDst},
		size = size_of(microui_state.color_buf),
	})
	h_microui_index_buffer := create_buffer(&renderer_manager, &{
		label = "microui index buffer",
		usage = {.Index, .CopyDst},
		size = size_of(microui_state.index_buf),
	})
	h_sun_buffer := create_buffer(&renderer_manager, &{
		label = "sun buffer",
		usage = {.Uniform, .CopyDst},
		size = size_of(SunUniform),
	})

	gbuffer := renderer_create_gbuffer(device, s_config)
	depth_texture_view := renderer_create_depth_texture_view(device, s_config)

	microui_atlas_texture_view, microui_atlas_texture, microui_sampler := microui_create_atlas_texture_view(device)

	shadow_texture, shadow_texture_view, shadow_sampler := renderer_create_shadow_map(device)

	h_global_bind_group_layout := create_bind_group_layout(&renderer_manager, "global layout group", {
		{
			binding = 0,
			visibility = {.Vertex, .Fragment},
			buffer = {
				type = .Uniform,
				hasDynamicOffset = false,
				minBindingSize = size_of(CameraUniform),
			},
		},
		{
			binding = 1,
			visibility = {.Vertex, .Fragment},
			buffer = {
				type = .Uniform,
				hasDynamicOffset = false,
				minBindingSize = size_of(RenderConfigUniform),
			},
		},
		{
			binding = 2,
			visibility = {.Fragment},
			buffer = {
				type = .ReadOnlyStorage,
				hasDynamicOffset = false,
				minBindingSize = size_of(linalg.Vector4f32) * 256,
			},
		},
		{
			binding = 3,
			visibility = {.Vertex},
			buffer = {
				type = .ReadOnlyStorage,
				hasDynamicOffset = false,
				minBindingSize = size_of(linalg.Matrix4f32) * constants.MAX_INSTANCES_COUNT,
			},
		},
	})
	h_global_bind_group := create_bind_group(&renderer_manager, "global bind group", h_global_bind_group_layout, {
		{binding = 0, buffer = get_buffer(&renderer_manager, h_camera_buffer), size = size_of(CameraUniform)},
		{binding = 1, buffer = get_buffer(&renderer_manager, h_render_config_buffer), size = size_of(RenderConfigUniform)},
		{binding = 2, buffer = get_buffer(&renderer_manager, h_palette_buffer), size = size_of(linalg.Vector4f32) * 256},
		{binding = 3, buffer = get_buffer(&renderer_manager, h_instance_buffer), size = size_of(linalg.Matrix4f32) * constants.MAX_INSTANCES_COUNT},
	})

	h_sun_bind_group_layout := create_bind_group_layout(&renderer_manager, "sun layout group", {
		{
			binding = 0,
			visibility = {.Vertex, .Fragment},
			buffer = {
				type = .Uniform,
				minBindingSize = size_of(SunUniform),
			},
		}
	})
	h_sun_bind_group := create_bind_group(&renderer_manager, "sun bind group", h_sun_bind_group_layout, {
		{binding = 0, buffer = get_buffer(&renderer_manager, h_sun_buffer), size = size_of(SunUniform)},
	})

	lighting_bind_group, lighting_layout_group := renderer_create_lighting_bind_group(
		device,
		&gbuffer,
		depth_texture_view,
		get_buffer(&renderer_manager, h_camera_buffer), 
		get_buffer(&renderer_manager, h_render_config_buffer),
		get_buffer(&renderer_manager, h_sun_buffer),
		shadow_texture_view,
		shadow_sampler,
	)
	microui_bind_group, microui_layout_group := microui_create_bind_group(
		device,
		microui_sampler,
		microui_atlas_texture_view,
		get_buffer(&renderer_manager, h_microui_constant_buffer),
	)

	microui_pipeline, microui_pipeline_layout := microui_create_pipeline(device, &microui_layout_group)
	shadow_pipeline, shadow_pipeline_layout := renderer_create_shadow_pipeline(
		device,
		get_bind_group_layout(&renderer_manager, h_global_bind_group_layout),
		get_bind_group_layout(&renderer_manager, h_sun_bind_group_layout),
	)
	lighting_pipeline, lighting_pipeline_layout := renderer_create_lighting_pipeline(device, &lighting_layout_group, s_config)

	microui_update_atlas_texture(queue, microui_atlas_texture)
	microui_update_constant(queue, get_buffer(&renderer_manager, h_microui_constant_buffer), window)

	return {
		device = device,
		queue = queue,
		window = window,
		renderer_manager = renderer_manager,
		use_wireframe = false,

		h_camera_buffer = h_camera_buffer,
		h_palette_buffer = h_palette_buffer,
		h_global_bind_group = h_global_bind_group,
		h_global_bind_group_layout = h_global_bind_group_layout,
		h_render_config_buffer = h_render_config_buffer,
		h_sun_buffer = h_sun_buffer,
		h_sun_bind_group = h_sun_bind_group,
		h_sun_bind_group_layout = h_sun_bind_group_layout,

		depth_texture_view = depth_texture_view,
		h_instance_buffer = h_instance_buffer,

		h_microui_vertex_buffer = h_microui_vertex_buffer,
		h_microui_texture_buffer = h_microui_texture_buffer,
		h_microui_color_buffer = h_microui_color_buffer,
		h_microui_index_buffer = h_microui_index_buffer,
		h_microui_constant_buffer = h_microui_constant_buffer,
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
		write_buffer_2(&r.renderer_manager, r.h_instance_buffer, &transforms)
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
	wgpu.RenderPassEncoderSetBindGroup(shadow_pass, 0, get_bind_group(&r.renderer_manager, r.h_global_bind_group))
	wgpu.RenderPassEncoderSetBindGroup(shadow_pass, 1, get_bind_group(&r.renderer_manager, r.h_sun_bind_group_layout))

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


	wgpu.RenderPassEncoderSetBindGroup(encoder, 0, get_bind_group(&r.renderer_manager, r.h_global_bind_group))

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
	wgpu.RenderPassEncoderSetVertexBuffer(encoder, 0, get_buffer(&r.renderer_manager, r.h_microui_vertex_buffer), 0, size_of(microui_state.vert_buf))
	wgpu.RenderPassEncoderSetVertexBuffer(encoder, 1, get_buffer(&r.renderer_manager, r.h_microui_texture_buffer), 0, size_of(microui_state.tex_buf))
	wgpu.RenderPassEncoderSetVertexBuffer(encoder, 2, get_buffer(&r.renderer_manager, r.h_microui_color_buffer), 0, size_of(microui_state.color_buf))
	wgpu.RenderPassEncoderSetIndexBuffer(encoder, get_buffer(&r.renderer_manager, r.h_microui_index_buffer), .Uint32, 0, size_of(microui_state.index_buf))

	microui_render(encoder, r.window, r.microui_ctx)

	wgpu.QueueWriteBuffer(r.queue, get_buffer(&r.renderer_manager, r.h_microui_vertex_buffer), 0, &microui_state.vert_buf, uint(microui_state.buf_idx*8*size_of(f32)))
	wgpu.QueueWriteBuffer(r.queue, get_buffer(&r.renderer_manager, r.h_microui_texture_buffer), 0, &microui_state.tex_buf, uint(microui_state.buf_idx*8*size_of(f32)))
	wgpu.QueueWriteBuffer(r.queue, get_buffer(&r.renderer_manager, r.h_microui_color_buffer), 0, &microui_state.color_buf, uint(microui_state.buf_idx*16))
	wgpu.QueueWriteBuffer(r.queue, get_buffer(&r.renderer_manager, r.h_microui_index_buffer), 0, &microui_state.index_buf, uint(microui_state.buf_idx*6*size_of(u32)))

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
		get_buffer(&r.renderer_manager, r.h_render_config_buffer),
		get_buffer(&r.renderer_manager, r.h_sun_buffer),
		r.shadow_texture_view,
		r.shadow_sampler,
	)

	microui_update_constant(r.queue, get_buffer(&r.renderer_manager, r.h_microui_constant_buffer), r.window)
}

renderer_destroy :: proc(r: ^Renderer) {
	renderer_manager_destroy(&r.renderer_manager)

	wgpu.TextureViewRelease(r.depth_texture_view)
	wgpu.TextureViewRelease(r.microui_atlas_texture_view)
	wgpu.TextureViewRelease(r.shadow_texture_view)

	wgpu.BindGroupRelease(r.microui_bind_group)
	wgpu.BindGroupRelease(r.lighting_bind_group)
	wgpu.BindGroupLayoutRelease(r.microui_layout_group)
	wgpu.BindGroupLayoutRelease(r.lighting_layout_group)

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
