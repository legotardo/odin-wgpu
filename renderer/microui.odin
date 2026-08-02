package renderer

import intr "base:intrinsics"
import "vendor:wgpu"
import "core:math/linalg"
import mu "vendor:microui"

import "../platform"

microui_shader_src := #load("../assets/shaders/microui.wgsl")

BUFFER_SIZE :: 16384

microui_state: struct {
    tex_buf:   [BUFFER_SIZE * 8]f32,
	vert_buf:  [BUFFER_SIZE * 8]f32,
	color_buf: [BUFFER_SIZE * 16]u8,
	index_buf: [BUFFER_SIZE * 6]u32,
	buf_idx:      u32,
}

microui_create_constant_buffer :: proc(device: wgpu.Device) -> wgpu.Buffer {
	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "microui constant buffer",
			usage = {.Uniform, .CopyDst},
			size = size_of(linalg.Matrix4f32),
		},
	)

	return buffer
}

microui_create_vertex_buffer :: proc(device: wgpu.Device) -> wgpu.Buffer {
	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "microui vertex buffer",
			usage = {.Vertex, .CopyDst},
			size = size_of(microui_state.vert_buf),
		},
	)

	return buffer
}

microui_create_tex_buffer :: proc(device: wgpu.Device) -> wgpu.Buffer {
	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "microui texture buffer",
			usage = {.Vertex, .CopyDst},
			size = size_of(microui_state.tex_buf),
		},
	)

	return buffer
}

microui_create_color_buffer :: proc(device: wgpu.Device) -> wgpu.Buffer {
	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "microui color buffer",
			usage = {.Vertex, .CopyDst},
			size = size_of(microui_state.color_buf),
		},
	)

	return buffer
}

microui_create_index_buffer :: proc(device: wgpu.Device) -> wgpu.Buffer {
	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "microui index buffer",
			usage = {.Index, .CopyDst},
			size = size_of(microui_state.index_buf),
		},
	)

	return buffer
}

microui_create_atlas_texture_view :: proc(device: wgpu.Device) -> (wgpu.TextureView, wgpu.Texture, wgpu.Sampler) {
	size := wgpu.Extent3D{
		width = mu.DEFAULT_ATLAS_WIDTH,
		height = mu.DEFAULT_ATLAS_HEIGHT,
		depthOrArrayLayers = 1,
	}

	descriptor := wgpu.TextureDescriptor {
		label = "MicroUI Atlas Texture Descriptor",
		size = size,
		mipLevelCount = 1,
		sampleCount = 1,
		dimension = ._2D,
		format = .R8Unorm,
		usage = {.TextureBinding, .CopyDst},
		viewFormats = {}
	}

	texture := wgpu.DeviceCreateTexture(device, &descriptor)
	sampler := wgpu.DeviceCreateSampler(device, &{
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

	atlas_texture := wgpu.TextureCreateView(texture, nil)

	return atlas_texture, texture, sampler
}

microui_create_bind_group :: proc(
    device: wgpu.Device,
	sampler: wgpu.Sampler,
	atlas_texture_view: wgpu.TextureView,
	constant_buffer: wgpu.Buffer,
) -> (wgpu.BindGroup, wgpu.BindGroupLayout) {
    layout_entries := [3]wgpu.BindGroupLayoutEntry {
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
	}


	global_layout_group := wgpu.DeviceCreateBindGroupLayout(
		device,
		&{
			entries = raw_data(layout_entries[:]),
			entryCount = len(layout_entries),
			label = "microui bind group layout",
		},
	)

	group_entries := [3]wgpu.BindGroupEntry {
		{binding = 0, sampler = sampler },
		{binding = 1, textureView = atlas_texture_view },
		{binding = 2, buffer = constant_buffer, size = size_of(linalg.Matrix4f32) },
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

    return global_bind_group, global_layout_group
}

microui_create_pipeline :: proc(device: wgpu.Device, bind_group_layouts: ^wgpu.BindGroupLayout) -> (wgpu.RenderPipeline, wgpu.PipelineLayout) {
	shader_module := wgpu.DeviceCreateShaderModule(
		device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = string(microui_shader_src) }},
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
			label = "microui render pipeline",
			layout = pipeline_layout,
			vertex = {
				module = shader_module,
				entryPoint = "vs_main",
				bufferCount = len(layouts),
				buffers = raw_data(layouts[:]),
			},
			fragment = &{
				module = shader_module,
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
			depthStencil = &wgpu.DepthStencilState{
				format = .Depth24Plus,
				depthWriteEnabled = .False,
				depthCompare = .Always,
				stencilFront = {},
				stencilBack = {},
				stencilReadMask = 0,
				stencilWriteMask = 0,
				depthBias = 0,
				depthBiasSlopeScale = 0,
				depthBiasClamp = 0,
			}
		},
	)

	return pipeline, pipeline_layout
}

microui_update_atlas_texture :: proc(queue: wgpu.Queue, atlas_texture: wgpu.Texture) {
	wgpu.QueueWriteTexture(
		queue,
		&{ texture = atlas_texture },
		&mu.default_atlas_alpha,
		mu.DEFAULT_ATLAS_WIDTH*mu.DEFAULT_ATLAS_HEIGHT,
		&{
			bytesPerRow  = mu.DEFAULT_ATLAS_WIDTH,
			rowsPerImage = mu.DEFAULT_ATLAS_HEIGHT,
		},
		&{ mu.DEFAULT_ATLAS_WIDTH, mu.DEFAULT_ATLAS_HEIGHT, 1 },
	)
}

microui_update_constant :: proc(
	queue: wgpu.Queue,
	constant_buffer: wgpu.Buffer,
	window: ^platform.Window,
) {
	dpi := platform.get_dpi(window)
	width, height := platform.get_frame_size(window)
	fw, fh := f32(width), f32(height)
	transform := linalg.matrix_ortho3d(0, fw, fh, 0, -1, 1) * linalg.matrix4_scale(dpi)

	wgpu.QueueWriteBuffer(queue, constant_buffer, 0, &transform, size_of(transform))
}

microui_draw_text :: proc(text: string, pos: mu.Vec2, color: mu.Color) {
	dst := mu.Rect{ pos.x, pos.y, 0, 0 }
	for ch in text {
		if ch&0xc0 != 0x80 {
			r := min(int(ch), 127)
			src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
			dst.w = src.w
			dst.h = src.h
			push_quad(dst, src, color)
			dst.x += dst.w
		}
	}
}

microui_draw_rect :: proc(rect: mu.Rect, color: mu.Color) {
	push_quad(rect, mu.default_atlas[mu.DEFAULT_ATLAS_WHITE], color)
}

microui_draw_icon :: proc(id: mu.Icon, rect: mu.Rect, color: mu.Color) {
	src := mu.default_atlas[id]
	x := rect.x + (rect.w - src.w) / 2
	y := rect.y + (rect.h - src.h) / 2
	push_quad({x, y, src.w, src.h}, src, color)
}

@(private="file")
push_quad :: proc(dst, src: mu.Rect, color: mu.Color) #no_bounds_check {
	r := &microui_state

	textvert_idx := r.buf_idx * 8
	color_idx    := r.buf_idx * 16
	element_idx  := u32(r.buf_idx * 4)
	index_idx    := r.buf_idx * 6

	r.buf_idx += 1

	x := f32(src.x) / mu.DEFAULT_ATLAS_WIDTH
	y := f32(src.y) / mu.DEFAULT_ATLAS_HEIGHT
	w := f32(src.w) / mu.DEFAULT_ATLAS_WIDTH
	h := f32(src.h) / mu.DEFAULT_ATLAS_HEIGHT
	copy(r.tex_buf[textvert_idx:], []f32{
		x,     y,
		x + w, y,
		x,     y + h,
		x + w, y + h,
	})

	dx, dy, dw, dh := f32(dst.x), f32(dst.y), f32(dst.w), f32(dst.h)
	copy(r.vert_buf[textvert_idx:], []f32{
		dx,      dy,
		dx + dw, dy,
		dx,      dy + dh,
		dx + dw, dy + dh,
	})

	color := color
	intr.mem_copy_non_overlapping(raw_data(r.color_buf[color_idx + 0:]),  &color, 4)
	intr.mem_copy_non_overlapping(raw_data(r.color_buf[color_idx + 4:]),  &color, 4)
	intr.mem_copy_non_overlapping(raw_data(r.color_buf[color_idx + 8:]),  &color, 4)
	intr.mem_copy_non_overlapping(raw_data(r.color_buf[color_idx + 12:]), &color, 4)

	copy(r.index_buf[index_idx:], []u32{
		element_idx + 0,
		element_idx + 1,
		element_idx + 2,
		element_idx + 2,
		element_idx + 3,
		element_idx + 1,
	})
}

microui_set_clip_rect :: proc(rect: mu.Rect, encoder: wgpu.RenderPassEncoder, window: ^platform.Window) {
	x := min(u32(rect.x), window.width)
	y := min(u32(rect.y), window.height)
	w := min(u32(rect.w), window.width-x)
	h := min(u32(rect.h), window.height-y)
	wgpu.RenderPassEncoderSetScissorRect(encoder, x, y, w, h)
}

microui_render :: proc(encoder: wgpu.RenderPassEncoder, window: ^platform.Window, ctx: ^mu.Context) {
	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(ctx, &command_backing) {
        switch cmd in variant {
            case ^mu.Command_Text: microui_draw_text(cmd.str, cmd.pos, cmd.color)
            case ^mu.Command_Rect: microui_draw_rect(cmd.rect, cmd.color)
            case ^mu.Command_Icon: microui_draw_icon(cmd.id, cmd.rect, cmd.color)
            case ^mu.Command_Clip: microui_set_clip_rect(cmd.rect, encoder, window)
            case ^mu.Command_Jump: unreachable() 
		}
    }
}
