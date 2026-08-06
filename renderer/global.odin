package renderer

import "vendor:wgpu"
import "core:math/linalg"
import "../constants"

renderer_create_global_bind_group :: proc(
    device: wgpu.Device,
    palette_buffer: wgpu.Buffer,
	camera_buffer:  wgpu.Buffer,
	light_buffer: wgpu.Buffer,
	instance_buffer: wgpu.Buffer,
	render_config_buffer:  wgpu.Buffer,
) -> (wgpu.BindGroup, wgpu.BindGroupLayout) {
    layout_entries := [5]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex, .Fragment},
			buffer = {
				type = .Uniform,
				hasDynamicOffset = false,
				minBindingSize = size_of(CameraUniform),
			},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			buffer = {
				type = .Uniform,
				hasDynamicOffset = false,
				minBindingSize = size_of(RenderConfigUniform),
			},
		},
		{
			binding = 2,
			visibility = {.Fragment},
			buffer = {
				type = .ReadOnlyStorage,
				hasDynamicOffset = false,
				minBindingSize = size_of(linalg.Vector4f32) * 256,
			},
		},
		{
			binding = 3,
			visibility = {.Fragment},
			buffer = {
				type = .ReadOnlyStorage,
				hasDynamicOffset = false,
				minBindingSize = size_of(u32) * 4 + size_of(LightData) * 1024,
			},
		},
		{
			binding = 4,
			visibility = {.Vertex},
			buffer = {
				type = .ReadOnlyStorage,
				hasDynamicOffset = false,
				minBindingSize = size_of(linalg.Matrix4f32) * constants.MAX_INSTANCES_COUNT,
			},
		},
	}


	global_layout_group := wgpu.DeviceCreateBindGroupLayout(
		device,
		&{
			entries = raw_data(layout_entries[:]),
			entryCount = len(layout_entries),
			label = "global bind group layout",
		},
	)

	group_entries := [5]wgpu.BindGroupEntry {
		{binding = 0, buffer = camera_buffer, size = size_of(CameraUniform)},
		{binding = 1, buffer = render_config_buffer, size = size_of(RenderConfigUniform)},
		{binding = 2, buffer = palette_buffer, size = size_of(linalg.Vector4f32) * 256},
		{binding = 3, buffer = light_buffer, size = size_of(u32) * 4 + size_of(LightData) * 1024},
		{binding = 4, buffer = instance_buffer, size = size_of(linalg.Matrix4f32) * constants.MAX_INSTANCES_COUNT},
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