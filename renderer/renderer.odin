package renderer

import "vendor:wgpu"

Renderer :: struct {
	device: wgpu.Device,
	queue:  wgpu.Queue,
	camera: RenderCamera,
}

RenderItem :: struct {
	mesh:     ^Mesh,
	material: ^Material,
}

renderer_init :: proc(device: wgpu.Device, queue: wgpu.Queue) -> Renderer {
	camera := render_camera_create(device)

	return {camera = camera, device = device, queue = queue}
}

renderer_draw :: proc(r: ^Renderer, target_view: wgpu.TextureView, items: []RenderItem) {
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

	wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, r.camera.bind_group)

	for item in items {
		wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, item.material.pipeline)
		wgpu.RenderPassEncoderSetVertexBuffer(
			render_pass_encoder,
			0,
			item.mesh.vertex_buffer,
			0,
			u64(size_of(Vertex) * item.mesh.vertex_count),
		)
		wgpu.RenderPassEncoderSetIndexBuffer(
			render_pass_encoder,
			item.mesh.index_buffer,
			.Uint16,
			0,
			u64(size_of(u16) * item.mesh.index_count),
		)
		wgpu.RenderPassEncoderDrawIndexed(
			render_pass_encoder,
			indexCount = item.mesh.index_count,
			instanceCount = 1,
			firstIndex = 0,
			baseVertex = 0,
			firstInstance = 0,
		)
	}

	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(r.queue, {command_buffer})
}

renderer_destroy :: proc(r: ^Renderer) {
	render_camera_destroy(&r.camera)

	wgpu.DeviceRelease(r.device)
	wgpu.QueueRelease(r.queue)
}
