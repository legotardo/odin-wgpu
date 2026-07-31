package renderer

import "core:math/linalg"
import "vendor:wgpu"

RenderCamera :: struct {
	buffer:            wgpu.Buffer,
	bind_group:        wgpu.BindGroup,
	bind_group_layout: wgpu.BindGroupLayout,
}

render_camera_create :: proc(device: wgpu.Device) -> RenderCamera {
	layout_entries := [1]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex},
			buffer = {
				type = .Uniform,
				hasDynamicOffset = false,
				minBindingSize = size_of(linalg.Matrix4f32),
			},
		},
	}


	layout := wgpu.DeviceCreateBindGroupLayout(
		device,
		&{
			entries = raw_data(layout_entries[:]),
			entryCount = len(layout_entries),
			label = "camera bind group layout",
		},
	)

	buffer := wgpu.DeviceCreateBuffer(
		device,
		&{
			label = "camera buffer",
			usage = {.Uniform, .CopyDst},
			size = size_of(linalg.Matrix4f32),
		},
	)

	bind_group := wgpu.DeviceCreateBindGroup(
		device,
		&{
			layout = layout,
			entries = raw_data(
				[]wgpu.BindGroupEntry {
					{binding = 0, buffer = buffer, size = size_of(linalg.Matrix4f32)},
				},
			),
			entryCount = 1,
			label = "camera bind group",
		},
	)

	return {buffer = buffer, bind_group = bind_group, bind_group_layout = layout}
}

render_camera_update :: proc(
	queue: wgpu.Queue,
	camera: ^RenderCamera,
	view_proj: linalg.Matrix4f32,
) {
	mat := view_proj
	wgpu.QueueWriteBuffer(queue, camera.buffer, 0, &mat, size_of(mat))
}

render_camera_destroy :: proc(camera: ^RenderCamera) {
	wgpu.BufferRelease(camera.buffer)
	wgpu.BindGroupRelease(camera.bind_group)
	wgpu.BindGroupLayoutRelease(camera.bind_group_layout)
}
