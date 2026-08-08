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
    for b in rm.buffers { wgpu.BufferRelease(b) }
    for t in rm.textures { wgpu.TextureRelease(t) }
    for t in rm.texture_views { wgpu.TextureViewRelease(t) }
    for s in rm.samplers { wgpu.SamplerRelease(s) }
    for b in rm.bind_group_layouts { wgpu.BindGroupLayoutRelease(b) }
    for b in rm.bind_groups { wgpu.BindGroupRelease(b) }
    for p in rm.pipeline_layouts { wgpu.PipelineLayoutRelease(p) }
    for p in rm.pipelines { wgpu.RenderPipelineRelease(p) }

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
    wgpu.BufferRelease(rm.buffers[handle])

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

get_bind_group_layout :: proc(rm: ^RendererManager, handle: Handle) -> wgpu.BindGroupLayout {
    return rm.bind_group_layouts[handle]
}

get_bind_group :: proc(rm: ^RendererManager, handle: Handle) -> wgpu.BindGroup {
    return rm.bind_groups[handle]
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
