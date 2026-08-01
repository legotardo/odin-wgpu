package renderer

import "core:fmt"
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