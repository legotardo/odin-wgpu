package renderer

import "core:fmt"
import "core:os"
import "core:math/linalg"
import "vendor:wgpu"

lighting_shader_src := #load("../../assets/shaders/lighting.wgsl")
shadow_shader_src := #load("../../assets/shaders/shadow.wgsl")

CameraUniform :: struct {
	view_proj: linalg.Matrix4f32,
	view_proj_inv: linalg.Matrix4f32,
	position: linalg.Vector3f32,
	_pad: f32,
}

RenderConfigUniform :: struct {
	render_distance: i32,
	block_size: f32,
	_padding: [2]i32,
}

SunUniform :: struct {
	view_proj: linalg.Matrix4f32,
	direction: linalg.Vector4f32,
	sky_zenith: linalg.Vector4f32,
	sky_horizon: linalg.Vector4f32,
}

renderer_get_instancing_items :: proc(items: []RenderItem) -> []linalg.Matrix4f32 {
	count := 0
    for item in items {
        if item.should_use_instance {
            count += 1
        }
    }

    transforms := make([]linalg.Matrix4f32, count)

	transform_idx := 0
	for item in items {
		if !item.should_use_instance {
			continue
		}

		transforms[transform_idx] = item.transform
		transform_idx += 1
    }

	return transforms
}

recreate_gbuffer :: proc(r: ^Renderer, width, height: u32) {
	create_target :: proc(
		rm: ^RendererManager,
		h_tex: ^Handle,
		h_view: ^Handle,
		width, height: u32,
		format: wgpu.TextureFormat,
		label: string,
	) {
		desc := wgpu.TextureDescriptor{
			label = label,
			size = {
				width = width,
				height = height,
				depthOrArrayLayers = 1,
			},
			mipLevelCount = 1,
			sampleCount = 1,
			dimension = ._2D,
			format = format,
			usage = {.RenderAttachment, .TextureBinding},
		}

		if h_tex^ == 0 {
			h_tex^ = create_texture(rm, &desc)
			h_view^ = create_texture_view(rm, h_tex^, nil)
		} else {
			update_texture(rm, h_tex^, &desc)
			update_texture_view(rm, h_view^, h_tex^, nil)
		}
	}

	create_target(&r.renderer_manager, &r.h_gbuffer_albedo_texture, &r.h_gbuffer_albedo_view, width, height, .BGRA8Unorm, "g-buffer albedo")
	create_target(&r.renderer_manager, &r.h_gbuffer_normal_texture, &r.h_gbuffer_normal_view, width, height, .RGBA16Float, "g-buffer normal")

	// Sampler does not need to change after crated once
	if r.h_gbuffer_sampler == 0 {
		r.h_gbuffer_sampler = create_sampler(&r.renderer_manager, &{
			label = "g-buffer sampler",
			addressModeU = .ClampToEdge,
			addressModeV = .ClampToEdge,
			addressModeW = .ClampToEdge,
			magFilter = .Nearest,
			minFilter = .Nearest,
			mipmapFilter = .Nearest,
			maxAnisotropy = 1,
		})
	}
}

@(private)
recreate_depth_buffer :: proc(r: ^Renderer, width, height: u32) {
	texture_desc := wgpu.TextureDescriptor{
		label = "depth buffer texture",
		size = {
			width = width,
			height = height,
			depthOrArrayLayers = 1,
		},
		mipLevelCount = 1,
		sampleCount = 1,
		dimension = ._2D,
		format = .Depth24Plus,
		usage = {.RenderAttachment, .TextureBinding},
		viewFormats = {}
	}
	if r.h_depth_texture == 0 {
		r.h_depth_texture = create_texture(&r.renderer_manager, &texture_desc)
	} else {
		update_texture(&r.renderer_manager, r.h_depth_texture, &texture_desc)
	}

	if r.h_depth_texture_view == 0 {
		r.h_depth_texture_view = create_texture_view(&r.renderer_manager, r.h_depth_texture, nil)
	} else {
		update_texture_view(&r.renderer_manager, r.h_depth_texture_view, r.h_depth_texture, nil)
	}
}

@(private)
recreate_lighting_bind_group :: proc(r: ^Renderer) {
	entries := []wgpu.BindGroupEntry{
		{ binding = 0, textureView = get_texture_view(&r.renderer_manager, r.h_gbuffer_albedo_view) },
		{ binding = 1, textureView = get_texture_view(&r.renderer_manager, r.h_gbuffer_normal_view) },
		{ binding = 2, textureView = get_texture_view(&r.renderer_manager, r.h_depth_texture_view) },
		{ binding = 3, sampler = get_sampler(&r.renderer_manager, r.h_gbuffer_sampler) },
		{ binding = 4, buffer = get_buffer(&r.renderer_manager, r.h_camera_buffer), offset = 0, size = size_of(CameraUniform) },
		{ binding = 5, buffer = get_buffer(&r.renderer_manager, r.h_render_config_buffer), offset = 0, size = size_of(RenderConfigUniform) },
		{ binding = 6, buffer = get_buffer(&r.renderer_manager, r.h_sun_buffer), offset = 0, size = size_of(SunUniform) },
		{ binding = 7, textureView = get_texture_view(&r.renderer_manager, r.h_shadow_texture_view) },
		{ binding = 8, sampler = get_sampler(&r.renderer_manager, r.h_shadow_sampler) },
	}

	if r.h_lighting_bind_group == 0 {
		r.h_lighting_bind_group = create_bind_group(&r.renderer_manager, "lighting bind group", r.h_lighting_bind_group_layout, entries)
	} else {
		update_bind_group(&r.renderer_manager, r.h_lighting_bind_group, "lighting bind group", r.h_lighting_bind_group_layout, entries)
	}
}

@(private)
recreate_shadow_pipeline :: proc(r: ^Renderer) {
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
}

@(private)
recreate_lighting_pipeline :: proc(r: ^Renderer, s_config: ^wgpu.SurfaceConfiguration) {
	// TODO: This will not work on wasm
	if ODIN_DEBUG {
		lighting_shader_src, err := os.read_entire_file_from_path("./assets/shaders/lighting.wgsl", context.allocator)
		defer delete(lighting_shader_src)
		if err != os.ERROR_NONE {
			fmt.eprintf("Error reading file info:", err)
			return
		}
	}
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
}

@(private)
render_items :: proc(
	encoder: wgpu.RenderPassEncoder,
	items: []RenderItem,
	ignore_pipeline: bool = false,
	camera_only: bool = true,
) {
	prev_pipeline: wgpu.RenderPipeline
	instance_idx: u32
	for item in items {
		item_instance_idx := instance_idx
		if item.should_use_instance {
			instance_idx += 1
		}

		if camera_only && !item.visible_in_camera {
			continue
		}

		if item.material.pipeline != prev_pipeline && !ignore_pipeline {
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
			firstInstance = item_instance_idx,
		)
	}
}
