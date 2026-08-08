package renderer

import "vendor:wgpu"

Handle :: distinct u32

RendererManager :: struct {
    device: wgpu.Device,
	queue: wgpu.Queue,

    buffers: [dynamic]wgpu.Buffer,
    textures: [dynamic]wgpu.Texture,
    texture_views: [dynamic]wgpu.TextureView,
    samplers: [dynamic]wgpu.Sampler,
    bind_groups: [dynamic]wgpu.BindGroup,
    bind_group_layouts: [dynamic]wgpu.BindGroupLayout,
    pipelines: [dynamic]wgpu.RenderPipeline,
    pipeline_layouts: [dynamic]wgpu.PipelineLayout,
}

renderer_manager_init :: proc(device: wgpu.Device, queue: wgpu.Queue) -> RendererManager {
    return {
        device = device,
        queue = queue,
        buffers = make([dynamic]wgpu.Buffer),
        textures = make([dynamic]wgpu.Texture),
        texture_views = make([dynamic]wgpu.TextureView),
        samplers = make([dynamic]wgpu.Sampler),
        bind_groups = make([dynamic]wgpu.BindGroup),
        bind_group_layouts = make([dynamic]wgpu.BindGroupLayout),
        pipelines = make([dynamic]wgpu.RenderPipeline),
        pipeline_layouts = make([dynamic]wgpu.PipelineLayout),
    }
}

renderer_manager_destroy :: proc(rm: ^RendererManager) {
    for b in rm.buffers { if b != nil { wgpu.BufferRelease(b) } }
    for t in rm.textures { if t != nil { wgpu.TextureRelease(t) } }
    for t in rm.texture_views { if t != nil { wgpu.TextureViewRelease(t) } }
    for s in rm.samplers { if s != nil { wgpu.SamplerRelease(s) } }
    for b in rm.bind_group_layouts { if b != nil { wgpu.BindGroupLayoutRelease(b) } }
    for b in rm.bind_groups { if b != nil { wgpu.BindGroupRelease(b) } }
    for p in rm.pipeline_layouts { if p != nil { wgpu.PipelineLayoutRelease(p) } }
    for p in rm.pipelines { if p != nil { wgpu.RenderPipelineRelease(p) } }

    delete(rm.buffers)
    delete(rm.textures)
    delete(rm.texture_views)
    delete(rm.samplers)
    delete(rm.bind_group_layouts)
    delete(rm.bind_groups)
    delete(rm.pipeline_layouts)
    delete(rm.pipelines)
}

create_buffer :: proc(rm: ^RendererManager, desc: ^wgpu.BufferDescriptor) -> Handle {
    buffer := wgpu.DeviceCreateBuffer(rm.device, desc)

    append(&rm.buffers, buffer)
    return Handle(len(rm.buffers) - 1)
}

update_buffer :: proc(rm: ^RendererManager, handle: Handle, desc: ^wgpu.BufferDescriptor) {
    if rm.buffers[handle] != nil {
        wgpu.BufferRelease(rm.buffers[handle])
    }

    rm.buffers[handle] = wgpu.DeviceCreateBuffer(rm.device, desc)
}

write_buffer :: proc(rm: ^RendererManager, handle: Handle, buffer_offset: u64, data: rawptr, size: uint) {
    wgpu.QueueWriteBuffer(rm.queue, rm.buffers[handle], buffer_offset, data, size)
}

write_buffer_2 :: proc(rm: ^RendererManager, handle: Handle, data: ^$T) {
    wgpu.QueueWriteBuffer(rm.queue, rm.buffers[handle], 0, data, size_of(T))
}

get_buffer :: proc(rm: ^RendererManager, handle: Handle) -> wgpu.Buffer {
    return rm.buffers[handle]
}

create_bind_group_layout :: proc(rm: ^RendererManager, label: string, entries: []wgpu.BindGroupLayoutEntry) -> Handle {
    layout := wgpu.DeviceCreateBindGroupLayout(rm.device, &{
        label = label,
        entries = raw_data(entries[:]),
        entryCount = len(entries),
    })

    append(&rm.bind_group_layouts, layout)
    return Handle(len(rm.bind_group_layouts) - 1)
}

create_bind_group :: proc(rm: ^RendererManager, label: string, layout_handle: Handle, entries: []wgpu.BindGroupEntry) -> Handle {
    layout := rm.bind_group_layouts[layout_handle]

    bind_group := wgpu.DeviceCreateBindGroup(rm.device, &{
        label = label,
        layout = layout,
        entries = raw_data(entries[:]),
        entryCount = len(entries),
    })

    append(&rm.bind_groups, bind_group)
    return Handle(len(rm.bind_groups) - 1)
}

update_bind_group :: proc(rm: ^RendererManager, handle: Handle, label: string, layout_handle: Handle, entries: []wgpu.BindGroupEntry) {
    if rm.bind_groups[handle] != nil {
		wgpu.BindGroupRelease(rm.bind_groups[handle])
	}
    
    layout := rm.bind_group_layouts[layout_handle]

    rm.bind_groups[handle] = wgpu.DeviceCreateBindGroup(rm.device, &{
		label = label,
		layout = layout,
		entries = raw_data(entries[:]),
		entryCount = len(entries),
	})
}

get_bind_group_layout :: proc(rm: ^RendererManager, handle: Handle) -> wgpu.BindGroupLayout {
    return rm.bind_group_layouts[handle]
}

get_bind_group :: proc(rm: ^RendererManager, handle: Handle) -> wgpu.BindGroup {
    return rm.bind_groups[handle]
}

delete_bind_group :: proc(rm: ^RendererManager, handle: Handle) {
    if rm.bind_groups[handle] != nil {
        wgpu.BindGroupRelease(rm.bind_groups[handle])
        rm.bind_groups[handle] = nil
    }
}

create_pipeline_layout :: proc(rm: ^RendererManager, label: string, bind_group_layout_handles: []Handle) -> Handle {
    bind_layouts := make([]wgpu.BindGroupLayout, len(bind_group_layout_handles), context.temp_allocator)
	for handle, i in bind_group_layout_handles {
		bind_layouts[i] = rm.bind_group_layouts[handle]
	}

    layout := wgpu.DeviceCreatePipelineLayout(rm.device, &{
        label = label,
        bindGroupLayoutCount = len(bind_layouts),
        bindGroupLayouts = raw_data(bind_layouts[:]),
        immediateSize = 0,
    })

    append(&rm.pipeline_layouts, layout)
    return Handle(len(rm.pipeline_layouts) - 1)
}

get_pipeline_layout :: proc(rm: ^RendererManager, handle: Handle) -> wgpu.PipelineLayout {
    return rm.pipeline_layouts[handle]
}

create_pipeline :: proc(rm: ^RendererManager, desc: ^wgpu.RenderPipelineDescriptor) -> Handle {
    pipeline := wgpu.DeviceCreateRenderPipeline(rm.device, desc)

    append(&rm.pipelines, pipeline)
    return Handle(len(rm.pipelines) - 1)
}

get_pipeline :: proc(rm: ^RendererManager, handle: Handle) -> wgpu.RenderPipeline {
    return rm.pipelines[handle]
}

create_texture :: proc(rm: ^RendererManager, desc: ^wgpu.TextureDescriptor) -> Handle {
    texture := wgpu.DeviceCreateTexture(rm.device, desc)

    append(&rm.textures, texture)
    return Handle(len(rm.textures) - 1)
}

update_texture :: proc(rm: ^RendererManager, handle: Handle, desc: ^wgpu.TextureDescriptor) {
    if rm.textures[handle] != nil {
        wgpu.TextureRelease(rm.textures[handle])
    }

    rm.textures[handle] = wgpu.DeviceCreateTexture(rm.device, desc)
}

get_texture :: proc(rm: ^RendererManager, handle: Handle) -> wgpu.Texture {
    return rm.textures[handle]
}

delete_texture :: proc(rm: ^RendererManager, handle: Handle) {
    if rm.textures[handle] != nil {
        wgpu.TextureRelease(rm.textures[handle])
        rm.textures[handle] = nil
    }
}

create_texture_view :: proc(rm: ^RendererManager, texture_handle: Handle, desc: ^wgpu.TextureViewDescriptor) -> Handle {
    texture := rm.textures[texture_handle]
    texture_view := wgpu.TextureCreateView(texture, desc)

    append(&rm.texture_views, texture_view)
    return Handle(len(rm.texture_views) - 1)
}

update_texture_view :: proc(rm: ^RendererManager, handle: Handle, texture_handle: Handle, desc: ^wgpu.TextureViewDescriptor) {
    if rm.texture_views[handle] != nil {
        wgpu.TextureViewRelease(rm.texture_views[handle])
    }

    texture := rm.textures[texture_handle]
    rm.texture_views[handle] = wgpu.TextureCreateView(texture, desc)
}

get_texture_view :: proc(rm: ^RendererManager, handle: Handle) -> wgpu.TextureView {
    return rm.texture_views[handle]
}

delete_texture_view :: proc(rm: ^RendererManager, handle: Handle) {
    if rm.texture_views[handle] != nil {
        wgpu.TextureViewRelease(rm.texture_views[handle])
        rm.texture_views[handle] = nil
    }
}

create_sampler :: proc(rm: ^RendererManager, desc: ^wgpu.SamplerDescriptor) -> Handle {
    sampler := wgpu.DeviceCreateSampler(rm.device, desc)

    append(&rm.samplers, sampler)
    return Handle(len(rm.samplers) - 1)
}

get_sampler :: proc(rm: ^RendererManager, handle: Handle) -> wgpu.Sampler {
    return rm.samplers[handle]
}

create_shader_module :: proc(rm: ^RendererManager, code: string) -> wgpu.ShaderModule {
    shader_module := wgpu.DeviceCreateShaderModule(
		rm.device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = code }},
	)

    return shader_module
}

delete_shader_module :: proc(shader: wgpu.ShaderModule) {
    wgpu.ShaderModuleRelease(shader)
}
