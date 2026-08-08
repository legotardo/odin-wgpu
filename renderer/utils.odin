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
// // // G-Buffer

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
		{ binding = 0, textureView = r.gbuffer.albedo_view },
		{ binding = 1, textureView = r.gbuffer.normal_view },
		{ binding = 2, textureView = get_texture_view(&r.renderer_manager, r.h_depth_texture_view) },
		{ binding = 3, sampler = r.gbuffer.sampler },
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
