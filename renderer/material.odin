package renderer

import "../logger"
import "vendor:wgpu"

Material :: struct {
	pipeline:        wgpu.RenderPipeline,
	pipeline_layout: wgpu.PipelineLayout,
}

material_create :: proc(
	r: ^Renderer,
	shader_src: string,
	vertex_layout: wgpu.VertexBufferLayout,
	bind_group_layouts: []wgpu.BindGroupLayout,
) -> Material {
	shader_module := wgpu.DeviceCreateShaderModule(
		r.device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = shader_src}},
	)
	defer wgpu.ShaderModuleRelease(shader_module)

	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		r.device,
		&{
			bindGroupLayouts = raw_data(bind_group_layouts[:]),
			bindGroupLayoutCount = len(bind_group_layouts),
			immediateSize = 0,
		},
	)

	layouts := [1]wgpu.VertexBufferLayout{vertex_layout}
	primiteves_extras: wgpu.PrimitiveStateExtras

	if (r.use_wireframe) {
		primiteves_extras = wgpu.PrimitiveStateExtras {
			chain = {next = nil, sType = .PrimitiveStateExtras},
			polygonMode = .Line,
			conservative = false,
		}
	}

	pipeline := wgpu.DeviceCreateRenderPipeline(
		r.device,
		&{
			layout = pipeline_layout,
			vertex = {
				module = shader_module,
				entryPoint = "vs_main",
				bufferCount = len(layouts),
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
			primitive = {
				topology = .TriangleList,
				frontFace = .CCW,
				nextInChain = (^wgpu.ChainedStruct)(&primiteves_extras),
				cullMode = r.use_wireframe ? .None : .Back,
			},
			multisample = {count = 1, mask = 0xFFFFFFFF},
			depthStencil = &{
				format = .Depth24Plus,
				depthWriteEnabled = .True,
				depthCompare = .Less,
				stencilBack = {},
				stencilFront = {},
			}
		},
	)

	logger.info("[MATERIAL] Material created with shader")

	return {pipeline = pipeline, pipeline_layout = pipeline_layout}
}

material_destroy :: proc(material: ^Material) {
	wgpu.RenderPipelineRelease(material.pipeline)
	wgpu.PipelineLayoutRelease(material.pipeline_layout)
}
