package renderer

import "../logger"
import "../renderer"
import "vendor:wgpu"

Material :: struct {
	pipeline:        wgpu.RenderPipeline,
	h_pipeline_layout: renderer.Handle,
}

material_create :: proc(
	r: ^Renderer,
	shader_src: string,
	bind_group_layouts: []renderer.Handle,
) -> Material {
	shader_module := wgpu.DeviceCreateShaderModule(
		r.device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = shader_src}},
	)
	defer wgpu.ShaderModuleRelease(shader_module)

	h_pipeline_layout := create_pipeline_layout(&r.renderer_manager, "material pipeline layout", bind_group_layouts)

	vertex_layout := vertex_get_buffer_layout()

	layouts := [1]wgpu.VertexBufferLayout{vertex_layout}
	primiteves_extras: wgpu.PrimitiveStateExtras

	if (r.use_wireframe) {
		primiteves_extras = wgpu.PrimitiveStateExtras {
			chain = {next = nil, sType = .PrimitiveStateExtras},
			polygonMode = .Line,
			conservative = false,
		}
	}

	color_targets := [2]wgpu.ColorTargetState{
		{
			format = .BGRA8Unorm,
			blend = nil,
			writeMask = wgpu.ColorWriteMaskFlags_All,
		},
		{
			format = .RGBA16Float,
			blend = nil,
			writeMask = wgpu.ColorWriteMaskFlags_All,
		},
	}

	pipeline := wgpu.DeviceCreateRenderPipeline(
		r.device,
		&{
			label = "material render pipeline",
			layout = get_pipeline_layout(&r.renderer_manager, h_pipeline_layout),
			vertex = {
				module = shader_module,
				entryPoint = "vs_main",
				bufferCount = len(layouts),
				buffers = raw_data(layouts[:]),
			},
			fragment = &{
				module = shader_module,
				entryPoint = "fs_main",
				targetCount = len(color_targets),
				targets = raw_data(color_targets[:])
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

	return {pipeline = pipeline, h_pipeline_layout = h_pipeline_layout}
}

material_destroy :: proc(material: ^Material) {
	wgpu.RenderPipelineRelease(material.pipeline)
	material.h_pipeline_layout = {}
}
