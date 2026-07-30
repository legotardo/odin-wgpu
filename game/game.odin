package game

import "vendor:wgpu"

Vertex :: struct {
	position: [3]f32,
	color:    [3]f32,
}

sample_vertex := [4]Vertex {
	{position = {-0.5, 0.5, 0}, color = {1, 0, 0}}, //
	{position = {-0.5, -0.5, 0}, color = {0, 1, 0}}, //
	{position = {0.5, -0.5, 0}, color = {0, 0, 1}}, //
	{position = {0.5, 0.5, 0}, color = {1, 0, 1}}, //
}

sample_indices := [6]u16 {
	0,
	1,
	3, //
	3,
	1,
	2,
}

vertex_to_wgpu :: proc(data: []$T) -> wgpu.VertexBufferLayout {
	@(static) attributes := [2]wgpu.VertexAttribute {
		{
			offset         = 0, //
			shaderLocation = 0, //
			format         = .Float32x3,
		},
		{
			offset         = u64(size_of([3]f32)), //
			shaderLocation = 1, //
			format         = .Float32x3,
		},
	}

	return {
		arrayStride = u64(size_of(T)),
		stepMode = .Vertex,
		attributeCount = len(attributes),
		attributes = raw_data(attributes[:]),
	}
}
