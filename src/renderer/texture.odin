package renderer

import "vendor:wgpu"

Texture :: struct {
	texture:    wgpu.Texture,
	view:       wgpu.TextureView,
	bind_group: wgpu.BindGroup,
	width:      u32,
	height:     u32,
}

texture_create :: proc(
	r: ^Renderer,
	data: [^]u8,
	data_size: uintptr,
	width, height: u32,
	sampler: wgpu.Sampler,
	bind_group_layout: wgpu.BindGroupLayout,
) -> ^Texture {
	if data == nil || data_size < uintptr(width) * uintptr(height) * 4 || width == 0 || height == 0 {
		return nil
	}

	result := new(Texture)
	result.width = width
	result.height = height
	result.texture = wgpu.DeviceCreateTexture(r.device, &{
		label = "texture",
		size = {width, height, 1},
		mipLevelCount = 1,
		sampleCount = 1,
		dimension = ._2D,
		format = .RGBA8Unorm,
		usage = {.TextureBinding, .CopyDst},
	})
	if result.texture == nil {
		free(result)
		return nil
	}

	wgpu.QueueWriteTexture(
		r.queue,
		&{texture = result.texture},
		data,
		uint(data_size),
		&{
			bytesPerRow = width * 4,
			rowsPerImage = height,
		},
		&{width, height, 1},
	)

	result.view = wgpu.TextureCreateView(result.texture, nil)
	if result.view == nil {
		wgpu.TextureRelease(result.texture)
		free(result)
		return nil
	}

	entries := [2]wgpu.BindGroupEntry {
		{binding = 0, sampler = sampler},
		{binding = 1, textureView = result.view},
	}
	result.bind_group = wgpu.DeviceCreateBindGroup(r.device, &{
		label = "texture bind group",
		layout = bind_group_layout,
		entryCount = len(entries),
		entries = raw_data(entries[:]),
	})
	if result.bind_group == nil {
		wgpu.TextureViewRelease(result.view)
		wgpu.TextureRelease(result.texture)
		free(result)
		return nil
	}

	return result
}

texture_destroy :: proc(texture: ^Texture) {
	if texture == nil do return
	if texture.bind_group != nil do wgpu.BindGroupRelease(texture.bind_group)
	if texture.view != nil do wgpu.TextureViewRelease(texture.view)
	if texture.texture != nil do wgpu.TextureRelease(texture.texture)
	free(texture)
}
