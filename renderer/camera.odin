package renderer

import "core:math/linalg"
import "vendor:wgpu"

Camera :: struct {
	eye:    linalg.Vector3f32,
	target: linalg.Vector3f32,
	up:     linalg.Vector3f32,
	aspect: f32,
	fovy:   f32,
	znear:  f32,
	zfar:   f32,
}

camera_new :: proc(width, height: u32) -> Camera {
	return {
		eye = {0, 1, 2},
		target = {0, 0, 0},
		up = {0, 1, 0},
		aspect = f32(width) / f32(height),
		fovy = 90 * linalg.RAD_PER_DEG,
		zfar = 100,
		znear = 0.1,
	}
}

camera_build_matrix :: proc(camera: ^Camera) -> linalg.Matrix4f32 {
	view := linalg.matrix4_look_at_f32(camera.eye, camera.target, camera.up)
	proj := linalg.matrix4_perspective_f32(camera.fovy, camera.aspect, camera.znear, camera.zfar)

	return proj * view
}

RenderCamera :: struct {
	data:              Camera,
	buffer:            wgpu.Buffer,
	bind_group:        wgpu.BindGroup,
	bind_group_layout: wgpu.BindGroupLayout,
}

render_camera_create :: proc(device: wgpu.Device, width, height: u32) -> RenderCamera {
	camera := camera_new(width, height)

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

	mat := camera_build_matrix(&camera)
	buffer := wgpu.DeviceCreateBufferWithDataTyped(
		device,
		&{label = "camera buffer", usage = {.Uniform, .CopyDst}},
		mat,
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

	return {
		data              = camera, //
		buffer            = buffer,
		bind_group        = bind_group,
		bind_group_layout = layout,
	}
}

render_camera_update :: proc(queue: wgpu.Queue, camera: ^RenderCamera) {
	mat := camera_build_matrix(&camera.data)
	wgpu.QueueWriteBuffer(queue, camera.buffer, 0, &mat, size_of(mat))
}

render_camera_destroy :: proc(camera: ^RenderCamera) {
	wgpu.BufferRelease(camera.buffer)
	wgpu.BindGroupRelease(camera.bind_group)
	wgpu.BindGroupLayoutRelease(camera.bind_group_layout)
}
