package renderer

import "core:math/linalg"
import "vendor:wgpu"

lighting_shader_src := #load("../assets/shaders/lighting.wgsl")
shadow_shader_src := #load("../assets/shaders/shadow.wgsl")

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

    for item, i in items {
        if !item.should_use_instance {
            continue
        }
        
		transforms[i] = item.transform
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
