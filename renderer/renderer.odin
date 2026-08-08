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
	microui_ctx: ^mu.Context,
	total_vertex_count: u64, // Used for debug

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
	h_lighting_bind_group: Handle,
	h_lighting_bind_group_layout: Handle,
	h_depth_texture: Handle,
	h_depth_texture_view: Handle,
	h_microui_atlas_texture: Handle,
	h_microui_atlas_texture_view: Handle,
	h_microui_sampler: Handle,
	h_microui_bind_group_layout: Handle,
	h_microui_bind_group: Handle,
	h_shadow_texture: Handle,
	h_shadow_texture_view: Handle,
	h_shadow_sampler: Handle,
	h_microui_pipeline: Handle,
	h_microui_pipeline_layout: Handle,
	h_shadow_pipeline: Handle,
	h_shadow_pipeline_layout: Handle,
	h_lighting_pipeline: Handle,
	h_lighting_pipeline_layout: Handle,
	h_gbuffer_albedo_texture: Handle,
	h_gbuffer_albedo_view: Handle,
	h_gbuffer_normal_texture: Handle,
	h_gbuffer_normal_view: Handle,
	h_gbuffer_sampler: Handle,
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
) -> (r: Renderer) {
	r.device = device
	r.queue = queue
	r.window = window
	r.renderer_manager = renderer_manager_init(device, queue)

	r.h_camera_buffer = create_buffer(&r.renderer_manager, &{
		label = "camera buffer",
		usage = {.Uniform, .CopyDst},
		size = size_of(CameraUniform),
	})
	r.h_palette_buffer = create_buffer(&r.renderer_manager, &{
		label = "palette buffer",
		usage = {.Storage, .CopyDst},
		size = size_of(linalg.Vector4f32) * 256,
	})
	r.h_render_config_buffer = create_buffer(&r.renderer_manager, &{
		label = "render config buffer",
		usage = {.Uniform, .CopyDst},
		size = size_of(RenderConfigUniform),
	})
	r.h_instance_buffer = create_buffer(&r.renderer_manager, &{
		label = "instance buffer",
		usage = {.Storage, .CopyDst},
		size = size_of(linalg.Matrix4f32) * constants.MAX_INSTANCES_COUNT,
	})
	r.h_microui_constant_buffer = create_buffer(&r.renderer_manager, &{
		label = "microui constant buffer",
		usage = {.Uniform, .CopyDst},
		size = size_of(linalg.Matrix4f32),
	})
	r.h_microui_vertex_buffer = create_buffer(&r.renderer_manager, &{
		label = "microui vertex buffer",
		usage = {.Vertex, .CopyDst},
		size = size_of(microui_state.vert_buf),
	})
	r.h_microui_texture_buffer = create_buffer(&r.renderer_manager, &{
		label = "microui texture buffer",
		usage = {.Vertex, .CopyDst},
		size = size_of(microui_state.tex_buf),
	})
	r.h_microui_color_buffer = create_buffer(&r.renderer_manager, &{
		label = "microui color buffer",
		usage = {.Vertex, .CopyDst},
		size = size_of(microui_state.color_buf),
	})
	r.h_microui_index_buffer = create_buffer(&r.renderer_manager, &{
		label = "microui index buffer",
		usage = {.Index, .CopyDst},
		size = size_of(microui_state.index_buf),
	})
	r.h_sun_buffer = create_buffer(&r.renderer_manager, &{
		label = "sun buffer",
		usage = {.Uniform, .CopyDst},
		size = size_of(SunUniform),
	})

	r.h_microui_atlas_texture = create_texture(&r.renderer_manager, &{
		label = "microui atlas texture",
		size = {
			width = mu.DEFAULT_ATLAS_WIDTH,
			height = mu.DEFAULT_ATLAS_HEIGHT,
			depthOrArrayLayers = 1,
		},
		mipLevelCount = 1,
		sampleCount = 1,
		dimension = ._2D,
		format = .R8Unorm,
		usage = {.TextureBinding, .CopyDst},
		viewFormats = {}
	})
	r.h_microui_atlas_texture_view = create_texture_view(&r.renderer_manager, r.h_microui_atlas_texture, nil)
	r.h_microui_sampler = create_sampler(&r.renderer_manager, &{
		label = "microui sampler",
		addressModeU = .ClampToEdge,
		addressModeV = .ClampToEdge,
		addressModeW = .ClampToEdge,
		magFilter = .Nearest,
		minFilter = .Nearest,
		mipmapFilter = .Nearest,
		compare = .Undefined,
		lodMinClamp = 0,
		lodMaxClamp = 32,
        maxAnisotropy = 1,
	})

	r.h_shadow_texture = create_texture(&r.renderer_manager, &{
		label = "shadow map texture",
		size = {
			width = 4096,
			height = 4096,
			depthOrArrayLayers = 1,
		},
		mipLevelCount = 1,
		sampleCount = 1,
		dimension = ._2D,
		format = .Depth32Float,
		usage = {.RenderAttachment, .TextureBinding},
		viewFormats = {},
		viewFormatCount = 0,
	})
	r.h_shadow_texture_view = create_texture_view(&r.renderer_manager, r.h_shadow_texture, nil)
	r.h_shadow_sampler = create_sampler(&r.renderer_manager, &{
		label = "shadow sampler",
		addressModeU = .ClampToEdge,
		addressModeV = .ClampToEdge,
		addressModeW = .ClampToEdge,
		magFilter = .Nearest,
		minFilter = .Nearest,
		mipmapFilter = .Nearest,
		maxAnisotropy = 1,
	})

	r.h_global_bind_group_layout = create_bind_group_layout(&r.renderer_manager, "global layout group", {
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
	r.h_global_bind_group = create_bind_group(&r.renderer_manager, "global bind group", r.h_global_bind_group_layout, {
		{binding = 0, buffer = get_buffer(&r.renderer_manager, r.h_camera_buffer), size = size_of(CameraUniform)},
		{binding = 1, buffer = get_buffer(&r.renderer_manager, r.h_render_config_buffer), size = size_of(RenderConfigUniform)},
		{binding = 2, buffer = get_buffer(&r.renderer_manager, r.h_palette_buffer), size = size_of(linalg.Vector4f32) * 256},
		{binding = 3, buffer = get_buffer(&r.renderer_manager, r.h_instance_buffer), size = size_of(linalg.Matrix4f32) * constants.MAX_INSTANCES_COUNT},
	})

	r.h_sun_bind_group_layout = create_bind_group_layout(&r.renderer_manager, "sun layout group", {
		{
			binding = 0,
			visibility = {.Vertex, .Fragment},
			buffer = {
				type = .Uniform,
				minBindingSize = size_of(SunUniform),
			},
		}
	})
	r.h_sun_bind_group = create_bind_group(&r.renderer_manager, "sun bind group", r.h_sun_bind_group_layout, {
		{binding = 0, buffer = get_buffer(&r.renderer_manager, r.h_sun_buffer), size = size_of(SunUniform)},
	})

	r.h_lighting_bind_group_layout = create_bind_group_layout(&r.renderer_manager, "lighting layout group", {
		{
			binding = 0,
			visibility = {.Fragment},
			texture = {
				sampleType = .UnfilterableFloat,
				viewDimension = ._2D,
				multisampled = false,
			},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			texture = {
				sampleType = .UnfilterableFloat,
				viewDimension = ._2D,
				multisampled = false,
			},
		},
		{
			binding = 2,
			visibility = {.Fragment},
			texture = {
				sampleType = .Depth,
				viewDimension = ._2D,
				multisampled = false,
			},
		},
		{
			binding = 3,
			visibility = {.Fragment},
			sampler = {
				type = .NonFiltering,
			},
		},
		{
			binding = 4,
			visibility = {.Fragment},
			buffer = {
				type = .Uniform,
				minBindingSize = size_of(CameraUniform)
			},
		},
		{
			binding = 5,
			visibility = {.Fragment},
			buffer = { type = .Uniform, minBindingSize = size_of(RenderConfigUniform) },
		},
		{
			binding = 6,
			visibility = {.Fragment},
			buffer = { type = .Uniform, minBindingSize = size_of(SunUniform) },
		},
		{
			binding = 7,
			visibility = {.Fragment},
			texture = { sampleType = .Depth, viewDimension = ._2D, multisampled = false },
		},
		{
			binding = 8,
			visibility = {.Fragment},
			sampler = { type = .NonFiltering },
		},
	})

	r.h_microui_bind_group_layout = create_bind_group_layout(&r.renderer_manager, "microui layout group", {
		{
			binding = 0,
			visibility = {.Fragment},
			sampler = {
				type = .Filtering,
			}
		},
		{
			binding = 1,
			visibility = {.Fragment},
			texture = {
				sampleType = .Float,
				viewDimension = ._2D,
				multisampled = false,
			}
		},
		{
			binding = 2,
			visibility = {.Vertex},
			buffer = {
				type = .Uniform,
				minBindingSize = size_of(linalg.Matrix4f32),
			},
		},
	})
	r.h_microui_bind_group = create_bind_group(&r.renderer_manager, "microui bind group", r.h_microui_bind_group_layout, {
		{binding = 0, sampler = get_sampler(&r.renderer_manager, r.h_microui_sampler) },
		{binding = 1, textureView = get_texture_view(&r.renderer_manager, r.h_microui_atlas_texture_view) },
		{binding = 2, buffer = get_buffer(&r.renderer_manager, r.h_microui_constant_buffer), size = size_of(linalg.Matrix4f32) },

	})

	microui_shader := create_shader_module(&r.renderer_manager, string(microui_shader_src))
	defer delete_shader_module(microui_shader)
	r.h_microui_pipeline_layout = create_pipeline_layout(&r.renderer_manager, "microui pipeline layout", {r.h_microui_bind_group_layout})
	microui_buffer_layout := [3]wgpu.VertexBufferLayout{
		{
			stepMode = .Vertex,
			arrayStride = 8,
			attributeCount = 1,
			attributes = &wgpu.VertexAttribute{
				format = .Float32x2,
				shaderLocation = 0,
			},
		},
		{
			stepMode = .Vertex,
			arrayStride = 8,
			attributeCount = 1,
			attributes = &wgpu.VertexAttribute{
				format = .Float32x2,
				shaderLocation = 1,
			},
		},
		{
			stepMode = .Vertex,
			arrayStride = 4,
			attributeCount = 1,
			attributes = &wgpu.VertexAttribute{
				format = .Uint32,
				shaderLocation = 2,
			},
		}
	}
	r.h_microui_pipeline = create_pipeline(&r.renderer_manager, &{
		label = "microui render pipeline",
		layout = get_pipeline_layout(&r.renderer_manager, r.h_microui_pipeline_layout),
		vertex = {
			module = microui_shader,
			entryPoint = "vs_main",
			buffers = raw_data(microui_buffer_layout[:]),
			bufferCount = len(microui_buffer_layout),
		},
		fragment = &{
			module = microui_shader,
			entryPoint = "fs_main",
			targetCount = 1,
			targets = &wgpu.ColorTargetState {
				format = .BGRA8Unorm,
				blend = &{
					alpha = {
						srcFactor = .SrcAlpha,
						dstFactor = .OneMinusSrcAlpha,
						operation = .Add,
					},
					color = {
						srcFactor = .SrcAlpha,
						dstFactor = .OneMinusSrcAlpha,
						operation = .Add,
					},
				},
				writeMask = wgpu.ColorWriteMaskFlags_All
			},
		},
		primitive = {
			topology = .TriangleList,
			cullMode = .None,
		},
		multisample = {count = 1, mask = 0xFFFFFFFF},
	})

	shadow_shader := create_shader_module(&r.renderer_manager, string(shadow_shader_src))
	defer delete_shader_module(shadow_shader)
	r.h_shadow_pipeline_layout = create_pipeline_layout(&r.renderer_manager, "shadow pipeline layout", {r.h_global_bind_group_layout, r.h_sun_bind_group_layout})
	vertex_layout := vertex_get_buffer_layout()
	r.h_shadow_pipeline = create_pipeline(&r.renderer_manager, &{
		label = "shadow render pipeline",
		layout = get_pipeline_layout(&r.renderer_manager, r.h_shadow_pipeline_layout),
		vertex = {
			module = shadow_shader,
			entryPoint = "vs_main",
			bufferCount = 1,
			buffers = &vertex_layout,
		},
		primitive = {
			topology = .TriangleList,
			frontFace = .CCW,
			cullMode = .Back,
		},
		multisample = {count = 1, mask = 0xFFFFFFFF},
		depthStencil = &{
			format = .Depth32Float,
			depthWriteEnabled = .True,
			depthCompare = .Less,
			depthBias = 2,
			depthBiasSlopeScale = 2.0,
			depthBiasClamp = 0.0,
		},
	})

	lighting_shader := create_shader_module(&r.renderer_manager, string(lighting_shader_src))
	defer delete_shader_module(lighting_shader)
	r.h_lighting_pipeline_layout = create_pipeline_layout(&r.renderer_manager, "lighting pipeline layout", {r.h_lighting_bind_group_layout})
	r.h_lighting_pipeline = create_pipeline(&r.renderer_manager, &{
		label = "lighting render pipeline",
		layout = get_pipeline_layout(&r.renderer_manager, r.h_lighting_pipeline_layout),
		vertex = {
			module = lighting_shader,
			entryPoint = "vs_main",
			bufferCount = 0,
			buffers = nil,
		},
		fragment = &{
			module = lighting_shader,
			entryPoint = "fs_main",
			targetCount = 1,
			targets = &wgpu.ColorTargetState {
				format = s_config.format,
				writeMask = wgpu.ColorWriteMaskFlags_All
			},
		},
		primitive = {
			topology = .TriangleList,
			frontFace = .CCW,
			cullMode = .None,
		},
		multisample = {count = 1, mask = 0xFFFFFFFF},
	})

	recreate_depth_buffer(&r, s_config.width, s_config.height)
	recreate_gbuffer(&r, s_config.width, s_config.height)
	recreate_lighting_bind_group(&r)

	microui_update_atlas_texture(queue, get_texture(&r.renderer_manager, r.h_microui_atlas_texture))
	microui_update_constant(queue, get_buffer(&r.renderer_manager, r.h_microui_constant_buffer), window)

	r.microui_ctx = microui_ctx

	return r
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
				view = get_texture_view(&r.renderer_manager, r.h_shadow_texture_view),
				depthLoadOp = .Clear,
				depthStoreOp = .Store,
				depthClearValue = 1.0,
				depthReadOnly = false,
			}
		},
	)

	wgpu.RenderPassEncoderSetPipeline(shadow_pass, get_pipeline(&r.renderer_manager, r.h_shadow_pipeline))
	wgpu.RenderPassEncoderSetBindGroup(shadow_pass, 0, get_bind_group(&r.renderer_manager, r.h_global_bind_group))
	wgpu.RenderPassEncoderSetBindGroup(shadow_pass, 1, get_bind_group(&r.renderer_manager, r.h_sun_bind_group))

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
			view = get_texture_view(&r.renderer_manager, r.h_gbuffer_albedo_view),
			loadOp = .Clear,
			storeOp = .Store,
			clearValue = {0.333, 0.721, 1.0, 1.0},
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		},
		{ 
			view = get_texture_view(&r.renderer_manager, r.h_gbuffer_normal_view),
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
				view = get_texture_view(&r.renderer_manager, r.h_depth_texture_view),
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

	wgpu.RenderPassEncoderSetPipeline(lighting_pass, get_pipeline(&r.renderer_manager, r.h_lighting_pipeline))
	wgpu.RenderPassEncoderSetBindGroup(lighting_pass, 0, get_bind_group(&r.renderer_manager, r.h_lighting_bind_group))
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
	wgpu.RenderPassEncoderSetPipeline(encoder, get_pipeline(&r.renderer_manager, r.h_microui_pipeline))
	wgpu.RenderPassEncoderSetBindGroup(encoder, 0, get_bind_group(&r.renderer_manager, r.h_microui_bind_group))
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
	recreate_depth_buffer(r, s_config.width, s_config.height)
	recreate_gbuffer(r, s_config.width, s_config.height)
	recreate_lighting_bind_group(r)

	microui_update_constant(r.queue, get_buffer(&r.renderer_manager, r.h_microui_constant_buffer), r.window)
}

renderer_destroy :: proc(r: ^Renderer) {
	renderer_manager_destroy(&r.renderer_manager)

	wgpu.DeviceRelease(r.device)
	wgpu.QueueRelease(r.queue)
}
