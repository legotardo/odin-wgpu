package renderer

import "vendor:wgpu"

Material :: struct {
	pipeline:        wgpu.RenderPipeline,
	pipeline_layout: wgpu.PipelineLayout,
}

material_create :: proc(
	device: wgpu.Device,
	shader_src: string,
	vertex_layout: wgpu.VertexBufferLayout,
	bind_group_layouts: []wgpu.BindGroupLayout,
) -> Material {
	shader_module := wgpu.DeviceCreateShaderModule(
		device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = shader_src}},
	)
	defer wgpu.ShaderModuleRelease(shader_module)

	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		device,
		&{
			bindGroupLayouts = raw_data(bind_group_layouts[:]),
			bindGroupLayoutCount = len(bind_group_layouts),
			immediateSize = 0,
		},
	)

	layouts := [1]wgpu.VertexBufferLayout{vertex_layout}

	pipeline := wgpu.DeviceCreateRenderPipeline(
		device,
		&{
			layout = pipeline_layout,
			vertex = {
				module = shader_module,
				entryPoint = "vs_main",
				bufferCount = 1,
				buffers = raw_data(layouts[:]),
			},
			fragment = &{
				module = shader_module,
				entryPoint = "fs_main",
				targetCount = 1,
				targets = &wgpu.ColorTargetState {
					format = .BGRA8Unorm,
					writeMask = wgpu.ColorWriteMaskFlags_All,
				},
			},
			primitive = {topology = .TriangleList},
			multisample = {count = 1, mask = 0xFFFFFFFF},
		},
	)

	return {pipeline = pipeline, pipeline_layout = pipeline_layout}
}

material_destroy :: proc(material: ^Material) {
	wgpu.RenderPipelineRelease(material.pipeline)
	wgpu.PipelineLayoutRelease(material.pipeline_layout)
}
