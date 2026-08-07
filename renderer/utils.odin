package renderer

import "core:math/linalg"
import "vendor:wgpu"
import "../constants"

// // // CAMERA
CameraUniform :: struct {
	view_proj: linalg.Matrix4f32,
	view_proj_inv: linalg.Matrix4f32,
	position: linalg.Vector3f32,
	_pad: f32,
}

renderer_create_camera_buffer :: proc(device: wgpu.Device) -> wgpu.Buffer {
	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "camera buffer",
			usage = {.Uniform, .CopyDst},
			size = size_of(CameraUniform),
		},
	)

	return buffer
}

renderer_update_camera_buffer :: proc(
	r: ^Renderer,
	uniform: CameraUniform,
) {
	mat := uniform
	wgpu.QueueWriteBuffer(r.queue, r.camera_buffer, 0, &mat, size_of(CameraUniform))
}
// // // CAMERA

// // // PALETTE
renderer_create_palette_buffer :: proc(device: wgpu.Device) -> wgpu.Buffer {
	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "palette buffer",
			usage = {.Storage, .CopyDst},
			size = size_of(linalg.Vector4f32) * 256,
		},
	)

	return buffer
}

renderer_update_palette_buffer :: proc(r: ^Renderer, colors: ^[256]linalg.Vector4f32) {
	wgpu.QueueWriteBuffer(r.queue, r.palette_buffer, 0, colors, size_of(linalg.Vector4f32) * 256)
}
// // // PALETTE

// // // DEPTH BUFFER
renderer_create_depth_texture_view :: proc(device: wgpu.Device, s_config: ^wgpu.SurfaceConfiguration) -> wgpu.TextureView {
	size := wgpu.Extent3D{
		width = s_config.width,
		height = s_config.height,
		depthOrArrayLayers = 1,
	}

	descriptor := wgpu.TextureDescriptor {
		label = "Depth Buffer Texture Descriptor",
		size = size,
		mipLevelCount = 1,
		sampleCount = 1,
		dimension = ._2D,
		format = .Depth24Plus,
		usage = {.RenderAttachment, .TextureBinding},
		viewFormats = {}
	}

	texture := wgpu.DeviceCreateTexture(device, &descriptor)
	// samples := wgpu.DeviceCreateSampler(r.device, &{
	// 	addressModeU = .ClampToEdge,
	// 	addressModeV = .ClampToEdge,
	// 	addressModeW = .ClampToEdge,
	// 	magFilter = .Linear,
	// 	minFilter = .Linear,
	// 	mipmapFilter = .Nearest,
	// 	compare = .LessEqual,
	// 	lodMinClamp = 0,
	// 	lodMaxClamp = 100,
	// })

	depth_view := wgpu.TextureCreateView(texture, nil)

	return depth_view
}
// // // DEPTH BUFFER

// // // LIGHT
renderer_create_light_buffer :: proc(device: wgpu.Device) -> wgpu.Buffer {
	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "light buffer",
			usage = {.Storage, .CopyDst},
			size = size_of(u32) * 4 + size_of(LightData) * 10246,
		},
	)

	return buffer
}

renderer_update_light_buffer :: proc(
	r: ^Renderer,
	lights: []LightData,
) {
	LightBufferHeader :: struct {
		light_count: u32,
		_pad1:       u32,
		_pad2:       u32,
		_pad3:       u32,
	}

	header := LightBufferHeader{
		light_count = u32(len(lights)),
	}

	wgpu.QueueWriteBuffer(
		r.queue,
		r.light_buffer,
		0,
		&header,
		size_of(LightBufferHeader)
	)

	wgpu.QueueWriteBuffer(
		r.queue,
		r.light_buffer,
		u64(size_of(LightBufferHeader)),
		raw_data(lights[:]),
		size_of(LightData) * len(lights)
	)
}
// // // LIGHT

// // // INSTANCE
renderer_create_instance_buffer :: proc(device: wgpu.Device) -> wgpu.Buffer {
	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "instance buffer",
			usage = {.Storage, .CopyDst},
			size = size_of(linalg.Matrix4f32) * constants.MAX_INSTANCES_COUNT,
		},
	)

	return buffer
}

renderer_update_instance_buffer :: proc(
	r: ^Renderer,
	transforms: []linalg.Matrix4f32,
) {
		wgpu.QueueWriteBuffer(r.queue, r.instance_buffer, 0, raw_data(transforms), size_of(linalg.Matrix4f32) * len(transforms))
}

renderer_get_instancing_items :: proc(items: []RenderItem) -> []linalg.Matrix4f32 {
	count := 0
    for item in items {
        if item.should_use_instance {
            count += 1
        }
    }

    transforms := make([]linalg.Matrix4f32, count)

    for item, i in items {
        if !item.should_use_instance {
            continue
        }
        
		transforms[i] = item.transform
    }

	return transforms
}

// // // Render Config
RenderConfigUniform :: struct {
	render_distance: i32,
	block_size: f32,
	_padding: [2]i32,
}

renderer_create_render_config_buffer :: proc(device: wgpu.Device) -> wgpu.Buffer {
	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "render config buffer",
			usage = {.Uniform, .CopyDst},
			size = size_of(RenderConfigUniform),
		},
	)

	return buffer
}

renderer_update_render_config_buffer :: proc(
	r: ^Renderer,
	uniform: RenderConfigUniform,
) {
	mat := uniform
	wgpu.QueueWriteBuffer(r.queue, r.render_config_buffer, 0, &mat, size_of(RenderConfigUniform))
}
// // // Render Config

// // // G-Buffer
GBuffer :: struct {
	albedo_texture:   wgpu.Texture,
	albedo_view:      wgpu.TextureView,
	normal_texture:   wgpu.Texture,
	normal_view:      wgpu.TextureView,
	sampler:          wgpu.Sampler,
}

renderer_create_gbuffer :: proc(device: wgpu.Device, s_config: ^wgpu.SurfaceConfiguration) -> GBuffer {
	size := wgpu.Extent3D{
		width = s_config.width,
		height = s_config.height,
		depthOrArrayLayers = 1,
	}

	create_target :: proc(device: wgpu.Device, size: wgpu.Extent3D, format: wgpu.TextureFormat, label: string) -> (wgpu.Texture, wgpu.TextureView) {
		descriptor := wgpu.TextureDescriptor{
			label = label,
			size = size,
			mipLevelCount = 1,
			sampleCount = 1,
			dimension = ._2D,
			format = format,
			usage = {.RenderAttachment, .TextureBinding},
			viewFormats = {},
		}
		texture := wgpu.DeviceCreateTexture(device, &descriptor)
		view := wgpu.TextureCreateView(texture, nil)
		return texture, view
	}

	albedo_tex, albedo_view := create_target(device, size, .BGRA8Unorm, "GBuffer Albedo")
	normal_tex, normal_view := create_target(device, size, .RGBA16Float, "GBuffer Normal")
	pos_tex, pos_view := create_target(device, size, .RGBA32Float, "GBuffer Position")

	sampler := wgpu.DeviceCreateSampler(device, &{
		label = "GBuffer Sampler",
		addressModeU = .ClampToEdge,
		addressModeV = .ClampToEdge,
		addressModeW = .ClampToEdge,
		magFilter = .Nearest,
		minFilter = .Nearest,
		mipmapFilter = .Nearest,
		maxAnisotropy = 1,
	})

	return {
		albedo_texture = albedo_tex,
		albedo_view = albedo_view,
		normal_texture = normal_tex,
		normal_view = normal_view,
		sampler = sampler,
	}
}

renderer_destroy_gbuffer :: proc(g: ^GBuffer) {
	wgpu.TextureViewRelease(g.albedo_view)
	wgpu.TextureRelease(g.albedo_texture)
	wgpu.TextureViewRelease(g.normal_view)
	wgpu.TextureRelease(g.normal_texture)
	wgpu.SamplerRelease(g.sampler)
}

// // // Lighting
renderer_create_lighting_bind_group :: proc(
	device: wgpu.Device,
	gbuffer: ^GBuffer,
	depth_texture_view: wgpu.TextureView,
	camera_buffer: wgpu.Buffer,
) -> (wgpu.BindGroup, wgpu.BindGroupLayout) {
	entries := [5]wgpu.BindGroupEntry{
		{ binding = 0, textureView = gbuffer.albedo_view },
		{ binding = 1, textureView = gbuffer.normal_view },
		{ binding = 2, textureView = depth_texture_view },
		{ binding = 3, sampler = gbuffer.sampler },
		{ binding = 4, buffer = camera_buffer, offset = 0, size = size_of(CameraUniform) },
	}

	layout_entries := [5]wgpu.BindGroupLayoutEntry {
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
	}

	layout := wgpu.DeviceCreateBindGroupLayout(
		device,
		&{
			entries = raw_data(layout_entries[:]),
			entryCount = len(layout_entries),
			label = "global bind group layout",
		},
	)

	bind_group := wgpu.DeviceCreateBindGroup(device, &{
		label = "Lighting Bind Group",
		layout = layout,
		entryCount = len(entries),
		entries = raw_data(entries[:]),
	})

	return bind_group, layout
}

lighting_shader_src := #load("../assets/shaders/lighting.wgsl")

renderer_create_lighting_pipeline :: proc(
	device: wgpu.Device,
	bind_group_layouts: ^wgpu.BindGroupLayout,
	s_config: ^wgpu.SurfaceConfiguration,
) -> (wgpu.RenderPipeline, wgpu.PipelineLayout) {
	shader_module := wgpu.DeviceCreateShaderModule(
		device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = string(lighting_shader_src) }},
	)
	defer wgpu.ShaderModuleRelease(shader_module)

	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		device,
		&{
			bindGroupLayouts = bind_group_layouts,
			bindGroupLayoutCount = 1,
		},
	)

	layouts := [3]wgpu.VertexBufferLayout{
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

	pipeline := wgpu.DeviceCreateRenderPipeline(
		device,
		&{
			label = "lighting render pipeline",
			layout = pipeline_layout,
			vertex = {
				module = shader_module,
				entryPoint = "vs_main",
			},
			fragment = &{
				module = shader_module,
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
		},
	)

	return pipeline, pipeline_layout
}