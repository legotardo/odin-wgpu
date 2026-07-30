package renderer

import "../game"
import "vendor:wgpu"

default_shader_src := #load("../assets/shaders/minimal.wgsl")

Renderer :: struct {
	device:        wgpu.Device,
	queue:         wgpu.Queue,
	quad_mesh:     Mesh,
	quad_material: Material,
	camera:        RenderCamera,
}

renderer_init :: proc(device: wgpu.Device, queue: wgpu.Queue, width, height: u32) -> Renderer {
	vertices, indices := quad_geometry()
	quad_mesh := mesh_create(device, vertices, indices)

	camera := render_camera_create(device, width, height)

	quad_material := material_create(
		device,
		string(default_shader_src),
		vertex_get_buffer_layout(),
		[]wgpu.BindGroupLayout{camera.bind_group_layout},
	)

	return {
		camera = camera,
		quad_material = quad_material,
		quad_mesh = quad_mesh,
		device = device,
		queue = queue,
	}
}

renderer_draw :: proc(r: ^Renderer, target_view: wgpu.TextureView) {
	encoder := wgpu.DeviceCreateCommandEncoder(r.device, nil)
	defer wgpu.CommandEncoderRelease(encoder)

	render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = target_view,
				loadOp = .Clear,
				storeOp = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = {0.47, 0.68, 0.87, 1},
			},
		},
	)

	wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, r.quad_material.pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, r.camera.bind_group, {})

	// for obj in objects {
	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass_encoder,
		0,
		r.quad_mesh.vertex_buffer,
		0,
		u64(size_of(Vertex) * r.quad_mesh.vertex_count),
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		render_pass_encoder,
		r.quad_mesh.index_buffer,
		.Uint16,
		0,
		u64(size_of(u16) * r.quad_mesh.index_count),
	)
	wgpu.RenderPassEncoderDrawIndexed(
		render_pass_encoder,
		indexCount = r.quad_mesh.index_count,
		instanceCount = 1,
		firstIndex = 0,
		baseVertex = 0,
		firstInstance = 0,
	)

	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(r.queue, {command_buffer})
}

renderer_destroy :: proc(r: ^Renderer) {
	wgpu.DeviceRelease(r.device)
	wgpu.QueueRelease(r.queue)

	mesh_destroy(&r.quad_mesh)
	material_destroy(&r.quad_material)
	render_camera_destroy(&r.camera)
}
