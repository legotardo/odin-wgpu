package renderer

import "core:math/linalg"
import "vendor:wgpu"

// // // CAMERA
renderer_create_camera_buffer :: proc(device: wgpu.Device) -> wgpu.Buffer {
	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "camera buffer",
			usage = {.Uniform, .CopyDst},
			size = size_of(linalg.Matrix4f32),
		},
	)

	return buffer
}

renderer_update_camera_buffer :: proc(
	r: ^Renderer,
	view_proj: linalg.Matrix4f32,
) {
	mat := view_proj
	wgpu.QueueWriteBuffer(r.queue, r.camera_buffer, 0, &mat, size_of(mat))
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