package renderer

import "core:math/linalg"
import "vendor:wgpu"
import "../constants"

// // // CAMERA
CameraUniform :: struct {
	view_proj: linalg.Matrix4f32,
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

    transforms := make([]linalg.Matrix4f32, count, context.temp_allocator)

    for item, i in items {
        if !item.should_use_instance {
            continue
        }
        
		transforms[i] = item.transform
    }

	return transforms
}