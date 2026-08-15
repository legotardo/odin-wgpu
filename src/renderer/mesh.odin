package renderer

import "vendor:wgpu"

Mesh :: struct {
	renderer: ^Renderer,
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

	index_count := u32(len(indices))
	vertex_count := u32(len(vertices))

	r.total_vertex_count += u64(vertex_count)

	return {
		vertex_buffer = vertex_buffer,
		index_buffer = index_buffer,
		index_count = index_count,
		vertex_count = vertex_count,
		renderer = r,
	}
}

mesh_destroy :: proc(mesh: ^Mesh) {
	mesh.renderer.total_vertex_count -= u64(mesh.vertex_count)

	wgpu.BufferRelease(mesh.vertex_buffer)
	wgpu.BufferRelease(mesh.index_buffer)
}
