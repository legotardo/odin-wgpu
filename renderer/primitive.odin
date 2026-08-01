package renderer

import "core:math/linalg"
import "vendor:wgpu"

Vertex :: struct {
	position: linalg.Vector3f32,
	material_id: u8,
	normal_id: u8,
}

vertex_get_buffer_layout :: proc() -> wgpu.VertexBufferLayout {
	@(static) attributes := [3]wgpu.VertexAttribute {
		{
			offset         = u64(offset_of(Vertex, position)), //
			shaderLocation = 0, //
			format         = .Float32x3,
		},
		{
			offset         = u64(offset_of(Vertex, material_id)), //
			shaderLocation = 1, //
			format         = .Uint8,
		},
		{
			offset         = u64(offset_of(Vertex, normal_id)), //
			shaderLocation = 2, //
			format         = .Uint8,
		},
	}

	return {
		arrayStride = u64(size_of(Vertex)),
		stepMode = .Vertex,
		attributeCount = len(attributes),
		attributes = raw_data(attributes[:]),
	}
}

quad_geometry :: proc() -> ([]Vertex, []u16) {
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