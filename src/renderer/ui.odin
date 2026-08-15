package renderer

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import stb_image "vendor:stb/image"
import "vendor:wgpu"

import "../../libs/rml-ui/Bindings/Odin/rmlui"
import "../platform"

UI_CONTEXT_NAME :: "main"
UI_MAX_DRAWS :: 4096
UI_UNIFORM_STRIDE :: 256

#assert(size_of(rmlui.Vertex) == 20)
#assert(offset_of(rmlui.Vertex, position) == 0)
#assert(offset_of(rmlui.Vertex, colour) == 8)
#assert(offset_of(rmlui.Vertex, tex_coord) == 12)

ui_start_tick: time.Tick

ui_shader_src :: #load("../../assets/shaders/rmlui.wgsl")

UIGeometry :: struct {
	vertex_buffer: wgpu.Buffer,
	index_buffer:  wgpu.Buffer,
	index_count:   u32,
}

UIDrawUniform :: struct {
	viewport:    [2]f32,
	translation: [2]f32,
}

UIRendererData :: struct {
	r:                    ^Renderer,
	encoder:              wgpu.RenderPassEncoder,
	pipeline:             wgpu.RenderPipeline,
	pipeline_layout:      wgpu.PipelineLayout,
	draw_bind_group:      wgpu.BindGroup,
	draw_bind_group_layout: wgpu.BindGroupLayout,
	texture_bind_group_layout: wgpu.BindGroupLayout,
	draw_uniform_buffer:  wgpu.Buffer,
	sampler:              wgpu.Sampler,
	default_texture:      ^Texture,
	viewport_width:       u32,
	viewport_height:      u32,
	draw_count:           u32,
	scissor_enabled:      bool,
}

UIState :: struct {
	render_interface: rmlui.Render_Interface,
	system_interface: rmlui.System_Interface,
	ctx:              rmlui.Context,
	initialized:      bool,
	ui_renderer_data: ^UIRendererData,
	documents:        [dynamic]^UIDocument,
}

UIDocument :: struct {
	ui:            ^UIState,
	handle:        rmlui.Document,
	path:          string,
	visible:       bool,
	watch_handles: [dynamic]platform.WatchFileHandle,

	data_models: [dynamic]rmlui.Data_Constructor,
	data_handles: [dynamic]rmlui.Data_Handle,
}

@(private = "file")
ui_data_type_from_type_info :: proc(info: ^runtime.Type_Info) -> (rmlui.Data_Type, bool) {
	base_info := runtime.type_info_base(info)
	switch base_info.id {
	case typeid_of(bool):
		return .Bool, true
	case typeid_of(i32):
		return .Int, true
	case typeid_of(f32):
		return .Float, true
	case typeid_of(f64):
		return .Double, true
	case typeid_of(u16):
		return .UInt16, true
	}
	return {}, false
}

ui_data_model_bind_struct :: proc(
	constructor: rmlui.Data_Constructor,
	type_name, binding_name: string,
	value: ^$T,
) -> bool {
	if constructor == nil || value == nil do return false

	info := runtime.type_info_base(type_info_of(T))
	struct_info, ok := info.variant.(runtime.Type_Info_Struct)
	if !ok do return false

	c_type_name := strings.clone_to_cstring(type_name)
	defer delete(c_type_name)
	data_struct := rmlui.rmlui_data_model_register_struct(constructor, c_type_name)
	if data_struct == nil do return false

	for index in 0 ..< int(struct_info.field_count) {
		data_type, supported := ui_data_type_from_type_info(struct_info.types[index])
		if !supported {
			fmt.eprintf("Unsupported RmlUi data type for field %s\n", struct_info.names[index])
			return false
		}

		c_field_name := strings.clone_to_cstring(struct_info.names[index])
		added := rmlui.rmlui_data_struct_add_member(data_struct, c_field_name, struct_info.offsets[index], data_type)
		delete(c_field_name)
		if !added do return false
	}

	c_binding_name := strings.clone_to_cstring(binding_name)
	defer delete(c_binding_name)
	return rmlui.rmlui_data_model_bind_struct(constructor, c_binding_name, data_struct, value)
}

ui_compile_geometry :: proc "c" (
	user_data: rawptr,
	vertices: [^]rmlui.Vertex,
	vertex_count: uintptr,
	indices: [^]i32,
	index_count: uintptr,
) -> rmlui.Handle {
	context = runtime.default_context()
	if vertices == nil || indices == nil || vertex_count == 0 || index_count == 0 do return 0

	render_data := cast(^UIRendererData)user_data
	geometry := new(UIGeometry)
	geometry.vertex_buffer = wgpu.DeviceCreateBufferWithDataSlice(
		render_data.r.device,
		&{label = "RmlUi vertex buffer", usage = {.Vertex}},
		vertices[:vertex_count],
	)
	geometry.index_buffer = wgpu.DeviceCreateBufferWithDataSlice(
		render_data.r.device,
		&{label = "RmlUi index buffer", usage = {.Index}},
		indices[:index_count],
	)
	geometry.index_count = u32(index_count)

	if geometry.vertex_buffer == nil || geometry.index_buffer == nil {
		if geometry.vertex_buffer != nil do wgpu.BufferRelease(geometry.vertex_buffer)
		if geometry.index_buffer != nil do wgpu.BufferRelease(geometry.index_buffer)
		free(geometry)
		return 0
	}

	return rmlui.Handle(uintptr(geometry))
}

ui_render_geometry :: proc "c" (
	user_data: rawptr,
	geometry_handle: rmlui.Handle,
	translation: rmlui.Vector2f,
	texture_handle: rmlui.Handle,
) {
	context = runtime.default_context()
	render_data := cast(^UIRendererData)user_data
	if render_data.encoder == nil || geometry_handle == 0 || render_data.draw_count >= UI_MAX_DRAWS do return

	geometry := cast(^UIGeometry)geometry_handle
	texture := render_data.default_texture
	if texture_handle != 0 {
		texture = cast(^Texture)texture_handle
	}
	if texture == nil do return

	offset := render_data.draw_count * UI_UNIFORM_STRIDE
	uniform := UIDrawUniform {
		viewport = {f32(render_data.viewport_width), f32(render_data.viewport_height)},
		translation = {translation.x, translation.y},
	}
	wgpu.QueueWriteBuffer(
		render_data.r.queue,
		render_data.draw_uniform_buffer,
		u64(offset),
		&uniform,
		size_of(uniform),
	)

	wgpu.RenderPassEncoderSetBindGroup(render_data.encoder, 0, render_data.draw_bind_group, {offset})
	wgpu.RenderPassEncoderSetBindGroup(render_data.encoder, 1, texture.bind_group)
	wgpu.RenderPassEncoderSetVertexBuffer(
		render_data.encoder,
		0,
		geometry.vertex_buffer,
		0,
		wgpu.WHOLE_SIZE,
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		render_data.encoder,
		geometry.index_buffer,
		.Uint32,
		0,
		wgpu.WHOLE_SIZE,
	)
	wgpu.RenderPassEncoderDrawIndexed(render_data.encoder, geometry.index_count, 1, 0, 0, 0)
	render_data.draw_count += 1
}

ui_release_geometry :: proc "c" (user_data: rawptr, geometry_handle: rmlui.Handle) {
	context = runtime.default_context()
	if geometry_handle == 0 do return
	geometry := cast(^UIGeometry)geometry_handle
	if geometry.vertex_buffer != nil do wgpu.BufferRelease(geometry.vertex_buffer)
	if geometry.index_buffer != nil do wgpu.BufferRelease(geometry.index_buffer)
	free(geometry)
}

ui_load_texture :: proc "c" (
	user_data: rawptr,
	dimensions: ^rmlui.Vector2i,
	source: rmlui.String_View,
) -> rmlui.Handle {
	context = runtime.default_context()
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		return 0
	} else {
		path, path_err := strings.clone_to_cstring(string(source.data[:source.length]), context.temp_allocator)
		if path_err != nil do return 0

		width, height, channels: c.int
		pixels := stb_image.load(path, &width, &height, &channels, 4)
		if pixels == nil || width <= 0 || height <= 0 do return 0
		defer stb_image.image_free(pixels)

		render_data := cast(^UIRendererData)user_data
		texture := texture_create(
			render_data.r,
			pixels,
			uintptr(width) * uintptr(height) * 4,
			u32(width),
			u32(height),
			render_data.sampler,
			render_data.texture_bind_group_layout,
		)
		if texture == nil do return 0
		dimensions^ = {width, height}
		return rmlui.Handle(uintptr(texture))
	}
}

ui_generate_texture :: proc "c" (
	user_data: rawptr,
	source: [^]u8,
	source_size: uintptr,
	dimensions: rmlui.Vector2i,
) -> rmlui.Handle {
	context = runtime.default_context()
	render_data := cast(^UIRendererData)user_data
	texture := texture_create(
		render_data.r,
		source,
		source_size,
		u32(dimensions.x),
		u32(dimensions.y),
		render_data.sampler,
		render_data.texture_bind_group_layout,
	)
	if texture == nil do return 0
	return rmlui.Handle(uintptr(texture))
}

ui_release_texture :: proc "c" (user_data: rawptr, texture_handle: rmlui.Handle) {
	context = runtime.default_context()
	if texture_handle != 0 do texture_destroy(cast(^Texture)texture_handle)
}

ui_set_full_scissor :: proc(render_data: ^UIRendererData) {
	if render_data.encoder == nil do return
	wgpu.RenderPassEncoderSetScissorRect(
		render_data.encoder,
		0,
		0,
		render_data.viewport_width,
		render_data.viewport_height,
	)
}

ui_enable_scissor_region :: proc "c" (user_data: rawptr, enable: rmlui.Bool) {
	context = runtime.default_context()
	render_data := cast(^UIRendererData)user_data
	render_data.scissor_enabled = enable != 0
	if !render_data.scissor_enabled do ui_set_full_scissor(render_data)
}

ui_set_scissor_region :: proc "c" (user_data: rawptr, region: rmlui.Rectanglei) {
	context = runtime.default_context()
	render_data := cast(^UIRendererData)user_data
	if render_data.encoder == nil || !render_data.scissor_enabled do return

	x := clamp(region.x, 0, i32(render_data.viewport_width))
	y := clamp(region.y, 0, i32(render_data.viewport_height))
	right := clamp(region.x + region.width, x, i32(render_data.viewport_width))
	bottom := clamp(region.y + region.height, y, i32(render_data.viewport_height))
	wgpu.RenderPassEncoderSetScissorRect(
		render_data.encoder,
		u32(x),
		u32(y),
		u32(right - x),
		u32(bottom - y),
	)
}

ui_get_elapsed_time :: proc "c" (user_data: rawptr) -> f64 {
	return time.duration_seconds(time.tick_since(ui_start_tick))
}

ui_log_message :: proc "c" (
	user_data: rawptr,
	message_type: i32,
	message: rmlui.String_View,
) -> rmlui.Bool {
	context = runtime.default_context()
	fmt.printf("RmlUi [%d]: %s\n", message_type, string(message.data[:message.length]))
	return 1
}

ui_set_mouse_cursor :: proc "c" (user_data: rawptr, cursor: rmlui.String_View) {
}

ui_set_clipboard_text :: proc "c" (user_data: rawptr, text: rmlui.String_View) {
}

ui_get_clipboard_text :: proc "c" (
	user_data: rawptr,
	buffer: [^]u8,
	buffer_size: uintptr,
) -> uintptr {
	return 0
}

ui_renderer_init :: proc(render_data: ^UIRendererData) {
	r := render_data.r
	render_data.draw_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(r.device, &{
		label = "RmlUi draw bind group layout",
		entryCount = 1,
		entries = &wgpu.BindGroupLayoutEntry {
			binding = 0,
			visibility = {.Vertex},
			buffer = {
				type = .Uniform,
				hasDynamicOffset = true,
				minBindingSize = size_of(UIDrawUniform),
			},
		},
	})

	texture_entries := [2]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Fragment},
			sampler = {type = .Filtering},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			texture = {
				sampleType = .Float,
				viewDimension = ._2D,
			},
		},
	}
	render_data.texture_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(r.device, &{
		label = "RmlUi texture bind group layout",
		entryCount = len(texture_entries),
		entries = raw_data(texture_entries[:]),
	})

	render_data.draw_uniform_buffer = wgpu.DeviceCreateBuffer(r.device, &{
		label = "RmlUi draw uniform buffer",
		usage = {.Uniform, .CopyDst},
		size = UI_MAX_DRAWS * UI_UNIFORM_STRIDE,
	})
	render_data.draw_bind_group = wgpu.DeviceCreateBindGroup(r.device, &{
		label = "RmlUi draw bind group",
		layout = render_data.draw_bind_group_layout,
		entryCount = 1,
		entries = &wgpu.BindGroupEntry {
			binding = 0,
			buffer = render_data.draw_uniform_buffer,
			size = size_of(UIDrawUniform),
		},
	})

	render_data.sampler = wgpu.DeviceCreateSampler(r.device, &{
		label = "RmlUi sampler",
		addressModeU = .ClampToEdge,
		addressModeV = .ClampToEdge,
		addressModeW = .ClampToEdge,
		magFilter = .Linear,
		minFilter = .Linear,
		mipmapFilter = .Nearest,
		maxAnisotropy = 1,
	})

	white := [4]u8{255, 255, 255, 255}
	render_data.default_texture = texture_create(
		r,
		raw_data(white[:]),
		len(white),
		1,
		1,
		render_data.sampler,
		render_data.texture_bind_group_layout,
	)

	bind_group_layouts := [2]wgpu.BindGroupLayout {
		render_data.draw_bind_group_layout,
		render_data.texture_bind_group_layout,
	}
	render_data.pipeline_layout = wgpu.DeviceCreatePipelineLayout(r.device, &{
		label = "RmlUi pipeline layout",
		bindGroupLayoutCount = len(bind_group_layouts),
		bindGroupLayouts = raw_data(bind_group_layouts[:]),
	})

	shader := create_shader_module(&r.renderer_manager, string(ui_shader_src))
	defer delete_shader_module(shader)
	attributes := [3]wgpu.VertexAttribute {
		{format = .Float32x2, offset = 0, shaderLocation = 0},
		{format = .Unorm8x4, offset = 8, shaderLocation = 1},
		{format = .Float32x2, offset = 12, shaderLocation = 2},
	}
	vertex_layout := wgpu.VertexBufferLayout {
		arrayStride = size_of(rmlui.Vertex),
		stepMode = .Vertex,
		attributeCount = len(attributes),
		attributes = raw_data(attributes[:]),
	}
	color_target := wgpu.ColorTargetState {
		format = .BGRA8Unorm,
		blend = &wgpu.BlendState {
			color = {
				srcFactor = .SrcAlpha,
				dstFactor = .OneMinusSrcAlpha,
				operation = .Add,
			},
			alpha = {
				srcFactor = .One,
				dstFactor = .OneMinusSrcAlpha,
				operation = .Add,
			},
		},
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	render_data.pipeline = wgpu.DeviceCreateRenderPipeline(r.device, &{
		label = "RmlUi render pipeline",
		layout = render_data.pipeline_layout,
		vertex = {
			module = shader,
			entryPoint = "vs_main",
			bufferCount = 1,
			buffers = &vertex_layout,
		},
		fragment = &wgpu.FragmentState {
			module = shader,
			entryPoint = "fs_main",
			targetCount = 1,
			targets = &color_target,
		},
		primitive = {
			topology = .TriangleList,
			frontFace = .CCW,
			cullMode = .None,
		},
		multisample = {count = 1, mask = 0xFFFFFFFF},
	})

	assert(render_data.draw_bind_group_layout != nil)
	assert(render_data.texture_bind_group_layout != nil)
	assert(render_data.draw_uniform_buffer != nil)
	assert(render_data.draw_bind_group != nil)
	assert(render_data.sampler != nil)
	assert(render_data.default_texture != nil)
	assert(render_data.pipeline_layout != nil)
	assert(render_data.pipeline != nil)
}

ui_renderer_destroy :: proc(render_data: ^UIRendererData) {
	if render_data == nil do return
	texture_destroy(render_data.default_texture)
	if render_data.pipeline != nil do wgpu.RenderPipelineRelease(render_data.pipeline)
	if render_data.pipeline_layout != nil do wgpu.PipelineLayoutRelease(render_data.pipeline_layout)
	if render_data.draw_bind_group != nil do wgpu.BindGroupRelease(render_data.draw_bind_group)
	if render_data.draw_uniform_buffer != nil do wgpu.BufferRelease(render_data.draw_uniform_buffer)
	if render_data.sampler != nil do wgpu.SamplerRelease(render_data.sampler)
	if render_data.texture_bind_group_layout != nil do wgpu.BindGroupLayoutRelease(render_data.texture_bind_group_layout)
	if render_data.draw_bind_group_layout != nil do wgpu.BindGroupLayoutRelease(render_data.draw_bind_group_layout)
	free(render_data)
}

ui_init :: proc(r: ^Renderer, window: ^platform.Window) -> (state: UIState) {
	ui_start_tick = time.tick_now()
	state.documents = make([dynamic]^UIDocument)
	state.ui_renderer_data = new(UIRendererData)
	state.ui_renderer_data.r = r
	ui_renderer_init(state.ui_renderer_data)

	callbacks := rmlui.Render_Callbacks {
		compile_geometry = ui_compile_geometry,
		render_geometry = ui_render_geometry,
		release_geometry = ui_release_geometry,
		load_texture = ui_load_texture,
		generate_texture = ui_generate_texture,
		release_texture = ui_release_texture,
		enable_scissor_region = ui_enable_scissor_region,
		set_scissor_region = ui_set_scissor_region,
	}
	state.render_interface = rmlui.rmlui_render_interface_create(&callbacks, state.ui_renderer_data)
	assert(state.render_interface != nil, "RmlUi failed to create the render interface")

	system_callbacks := rmlui.System_Callbacks {
		get_elapsed_time = ui_get_elapsed_time,
		log_message = ui_log_message,
		set_mouse_cursor = ui_set_mouse_cursor,
		set_clipboard_text = ui_set_clipboard_text,
		get_clipboard_text = ui_get_clipboard_text,
	}
	state.system_interface = rmlui.rmlui_system_interface_create(&system_callbacks, nil)
	assert(state.system_interface != nil, "RmlUi failed to create the system interface")

	rmlui.rmlui_set_render_interface(state.render_interface)
	rmlui.rmlui_set_system_interface(state.system_interface)
	assert(rmlui.rmlui_initialise() != 0, "RmlUi failed to initialise")
	state.initialized = true

	width, height := platform.get_frame_size(window)
	state.ui_renderer_data.viewport_width = width
	state.ui_renderer_data.viewport_height = height
	state.ctx = rmlui.rmlui_context_create(UI_CONTEXT_NAME, {i32(width), i32(height)}, state.render_interface)
	assert(state.ctx != nil, "RmlUi failed to create the main context")
	assert(rmlui.rmlui_debugger_initialise(state.ctx) != 0, "Failed to initialise RmlUi debugger")
	assert(rmlui.rmlui_load_font_face("assets/fonts/Roboto-Regular.ttf", 0) != 0, "Failed to load the RmlUi font")

	return state
}

ui_draw :: proc(state: ^UIState, encoder: wgpu.RenderPassEncoder) {
	if state.ctx == nil do return
	rmlui.rmlui_context_update(state.ctx)
	render_data := state.ui_renderer_data
	render_data.encoder = encoder
	render_data.draw_count = 0
	render_data.scissor_enabled = false
	wgpu.RenderPassEncoderSetPipeline(encoder, render_data.pipeline)
	ui_set_full_scissor(render_data)
	rmlui.rmlui_context_render(state.ctx)
	render_data.encoder = nil
}

ui_resize :: proc(state: ^UIState, width, height: u32) {
	if state.ctx == nil do return
	state.ui_renderer_data.viewport_width = width
	state.ui_renderer_data.viewport_height = height
	rmlui.rmlui_context_set_dimensions(state.ctx, {i32(width), i32(height)})
}

ui_destroy :: proc(state: ^UIState) {
	for document in state.documents {
		if document != nil do ui_destroy_document(document)
	}
	delete(state.documents)
	state.documents = nil
	if state.ctx != nil {
		rmlui.rmlui_debugger_shutdown()
		rmlui.rmlui_context_remove(UI_CONTEXT_NAME)
		state.ctx = nil
	}
	if state.initialized {
		rmlui.rmlui_shutdown()
		state.initialized = false
	}
	if state.render_interface != nil {
		rmlui.rmlui_render_interface_destroy(state.render_interface)
		state.render_interface = nil
	}
	if state.system_interface != nil {
		rmlui.rmlui_system_interface_destroy(state.system_interface)
		state.system_interface = nil
	}
	ui_renderer_destroy(state.ui_renderer_data)
	state.ui_renderer_data = nil
}

@(private = "file")
ui_create_document :: proc(state: ^UIState, data, source_url: string) -> rmlui.Document {
	c_data := strings.clone_to_cstring(data)
	defer delete(c_data)
	c_source_url := strings.clone_to_cstring(source_url)
	defer delete(c_source_url)
	return rmlui.rmlui_context_load_document_from_memory(state.ctx, c_data, c_source_url)
}

@(private = "file")
ui_document_watch_callback :: proc(data: rawptr) {
	document := cast(^UIDocument)data
	if document != nil do ui_reload_document(document)
}

ui_watch_document_file :: proc(document: ^UIDocument, path: string) {
	if document == nil do return
	handle := platform.watch_file(path, ui_document_watch_callback, document)
	if handle != platform.WATCH_FILE_INVALID {
		append(&document.watch_handles, handle)
	}
}

ui_load_document :: proc(
	state: ^UIState,
	path: string,
	embedded_data: []u8,
	dependencies: ..string,
) -> ^UIDocument {
	if state == nil || state.ctx == nil do return nil

	source := string(embedded_data)
	file_data: []u8
	if ODIN_DEBUG {
		data, err := os.read_entire_file_from_path(path, context.temp_allocator)
		if err == os.ERROR_NONE {
			file_data = data
			source = string(file_data)
		} else {
			fmt.eprintf("Failed to read RmlUi document %s: %v\n", path, err)
		}
	}

	handle := ui_create_document(state, source, path)
	if handle == nil {
		fmt.eprintf("Failed to load RmlUi document %s\n", path)
		return nil
	}

	document := new(UIDocument)
	document.ui = state
	document.handle = handle
	document.path = strings.clone(path)
	document.watch_handles = make([dynamic]platform.WatchFileHandle)
	document.data_models = make([dynamic]rmlui.Data_Constructor)
	document.data_handles = make([dynamic]rmlui.Data_Handle)
	append(&state.documents, document)

	ui_watch_document_file(document, path)
	for dependency in dependencies {
		ui_watch_document_file(document, dependency)
	}
	return document
}

ui_load_document_with_model :: proc(
	state: ^UIState,
	path: string,
	embedded_data: []u8,
	model_name, binding_name: string,
	value: ^$T,
	dependencies: ..string,
) -> (document: ^UIDocument, model: rmlui.Data_Handle) {
	if state == nil || state.ctx == nil || value == nil do return

	c_model_name := strings.clone_to_cstring(model_name)
	defer delete(c_model_name)
	constructor := rmlui.rmlui_data_model_create(state.ctx, c_model_name)
	if constructor == nil {
		fmt.eprintf("Failed to create RmlUi data model %s\n", model_name)
		return
	}

	type_name := strings.concatenate({model_name, "_", binding_name}, context.temp_allocator)
	if !ui_data_model_bind_struct(constructor, type_name, binding_name, value) {
		fmt.eprintf("Failed to bind RmlUi data model %s\n", model_name)
		rmlui.rmlui_data_model_destroy_constructor(constructor)
		return
	}

	model = rmlui.rmlui_data_model_get_handle(constructor)
	if model == nil {
		rmlui.rmlui_data_model_destroy_constructor(constructor)
		return
	}

	document = ui_load_document(state, path, embedded_data, ..dependencies)
	if document == nil {
		rmlui.rmlui_data_handle_destroy(model)
		rmlui.rmlui_data_model_destroy_constructor(constructor)
		model = nil
		return
	}

	append(&document.data_models, constructor)
	append(&document.data_handles, model)
	return
}

ui_reload_document :: proc(document: ^UIDocument) -> bool {
	if document == nil || document.ui == nil || document.ui.ctx == nil do return false

	data, err := os.read_entire_file_from_path(document.path, context.temp_allocator)
	if err != os.ERROR_NONE {
		fmt.eprintf("Failed to reload RmlUi document %s: %v\n", document.path, err)
		return false
	}

	new_handle := ui_create_document(document.ui, string(data), document.path)
	if new_handle == nil {
		fmt.eprintf("Failed to reload RmlUi document %s, keeping the previous version\n", document.path)
		return false
	}

	old_handle := document.handle
	document.handle = new_handle
	if document.visible do rmlui.rmlui_document_show(new_handle)
	if old_handle != nil {
		rmlui.rmlui_context_unload_document(document.ui.ctx, old_handle)
	}
	fmt.printf("Reloaded RmlUi document %s\n", document.path)
	return true
}

ui_show :: proc(document: ^UIDocument) {
	if document == nil || document.handle == nil do return
	document.visible = true
	rmlui.rmlui_document_show(document.handle)
}

ui_hide :: proc(document: ^UIDocument) {
	if document == nil || document.handle == nil do return
	document.visible = false
	rmlui.rmlui_document_hide(document.handle)
}

ui_destroy_document :: proc(document: ^UIDocument) {
	if document == nil do return

	for handle in document.watch_handles {
		platform.unwatch_file(handle)
	}
	delete(document.watch_handles)

	for handle in document.data_handles {
		rmlui.rmlui_data_handle_destroy(handle)
	}
	delete(document.data_handles)

	for model in document.data_models {
		rmlui.rmlui_data_model_destroy_constructor(model)
	}
	delete(document.data_models)

	if document.handle != nil && document.ui != nil && document.ui.ctx != nil {
		rmlui.rmlui_context_unload_document(document.ui.ctx, document.handle)
		document.handle = nil
	}
	if document.ui != nil {
		for &registered_document in document.ui.documents {
			if registered_document == document {
				registered_document = nil
				break
			}
		}
	}

	delete(document.path)
	free(document)
}
