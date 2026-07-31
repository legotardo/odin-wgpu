package renderer

import "../logger"
import "vendor:wgpu"

Mesh :: struct {
	vertex_buffer: wgpu.Buffer,
	vertex_count:  u32,
	index_buffer:  wgpu.Buffer,
	index_count:   u32,
}

mesh_create :: proc(r: ^Renderer, vertices: []Vertex, indices: []u16) -> Mesh {
	vertex_buffer := wgpu.DeviceCreateBufferWithDataSlice(
		r.device,
		&{label = "mesh vertex buffer", usage = {.Vertex}},
		vertices[:],
	)
	index_buffer := wgpu.DeviceCreateBufferWithDataSlice(
		r.device,
		&{label = "index buffer", usage = {.Index}},
		indices[:],
	)

	logger.info("[MESH] Mesh created")

	return {
		vertex_buffer = vertex_buffer,
		index_buffer = index_buffer,
		index_count = u32(len(indices)),
		vertex_count = u32(len(vertices)),
	}
}

mesh_destroy :: proc(mesh: ^Mesh) {
	wgpu.BufferRelease(mesh.vertex_buffer)
	wgpu.BufferRelease(mesh.index_buffer)
}
