package renderer

import "core:math/linalg"
import "vendor:wgpu"

Vertex :: struct {
	position: linalg.Vector3f32,
	material_id: u8
	// color:    linalg.Vector3f32,
}

quad_geometry :: proc() -> ([]Vertex, []u16) {
	// @(static) vertices := [4]Vertex {
	// 	{position = {-0.5, 0.5, 0}, color = {1, 0, 0}}, //
	// 	{position = {-0.5, -0.5, 0}, color = {0, 1, 0}}, //
	// 	{position = {0.5, -0.5, 0}, color = {0, 0, 1}}, //
	// 	{position = {0.5, 0.5, 0}, color = {1, 0, 1}}, //
	// }
	@(static) vertices := [4]Vertex {
		{position = {-0.5, 0.5, 0}}, //
		{position = {-0.5, -0.5, 0}}, //
		{position = {0.5, -0.5, 0}}, //
		{position = {0.5, 0.5, 0}}, //
	}

	@(static) indices := [6]u16 {
		0,
		1,
		3, //
		3,
		1,
		2,
	}

	return vertices[:], indices[:]
}

vertex_get_buffer_layout :: proc() -> wgpu.VertexBufferLayout {
	@(static) attributes := [2]wgpu.VertexAttribute {
		{
			offset         = 0, //
			shaderLocation = 0, //
			format         = .Float32x3,
		},
		{
			offset         = u64(size_of([3]f32)), //
			shaderLocation = 1, //
			format         = .Uint8,
		},
		// {
		// 	offset         = u64(size_of([3]f32)), //
		// 	shaderLocation = 1, //
		// 	format         = .Float32x3,
		// },
	}

	return {
		arrayStride = u64(size_of(Vertex)),
		stepMode = .Vertex,
		attributeCount = len(attributes),
		attributes = raw_data(attributes[:]),
	}
}
