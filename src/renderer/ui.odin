package renderer

import "core:fmt"
import "core:time"
import "base:runtime"

import "../../libs/rml-ui/Bindings/Odin/rmlui"
import "../platform"

UI_CONTEXT_NAME :: "main"

ui_start_tick: time.Tick

UIState :: struct {
	render_interface: rmlui.Render_Interface,
	system_interface: rmlui.System_Interface,
	ctx:              rmlui.Context,
	initialized:      bool,
}

ui_compile_geometry :: proc "c" (
	user_data: rawptr,
	vertices: [^]rmlui.Vertex,
	vertex_count: uintptr,
	indices: [^]i32,
	index_count: uintptr,
) -> rmlui.Handle {
	return 0
}

ui_render_geometry :: proc "c" (
	user_data: rawptr,
	geometry: rmlui.Handle,
	translation: rmlui.Vector2f,
	texture: rmlui.Handle,
) {
}

ui_release_geometry :: proc "c" (user_data: rawptr, geometry: rmlui.Handle) {
}

ui_load_texture :: proc "c" (
	user_data: rawptr,
	dimensions: ^rmlui.Vector2i,
	source: rmlui.String_View,
) -> rmlui.Handle {
	return 0
}

ui_generate_texture :: proc "c" (
	user_data: rawptr,
	source: [^]u8,
	source_size: uintptr,
	dimensions: rmlui.Vector2i,
) -> rmlui.Handle {
	return 0
}

ui_release_texture :: proc "c" (user_data: rawptr, texture: rmlui.Handle) {
}

ui_enable_scissor_region :: proc "c" (user_data: rawptr, enable: rmlui.Bool) {
}

ui_set_scissor_region :: proc "c" (user_data: rawptr, region: rmlui.Rectanglei) {
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

ui_init :: proc(window: ^platform.Window) -> (state: UIState) {
	ui_start_tick = time.tick_now()
	callbacks := rmlui.Render_Callbacks {
		compile_geometry       = ui_compile_geometry,
		render_geometry        = ui_render_geometry,
		release_geometry       = ui_release_geometry,
		load_texture           = ui_load_texture,
		generate_texture       = ui_generate_texture,
		release_texture        = ui_release_texture,
		enable_scissor_region  = ui_enable_scissor_region,
		set_scissor_region     = ui_set_scissor_region,
	}

	state.render_interface = rmlui.rmlui_render_interface_create(&callbacks, nil)
	assert(state.render_interface != nil, "RmlUi failed to create the render interface")
	system_callbacks := rmlui.System_Callbacks {
		get_elapsed_time   = ui_get_elapsed_time,
		log_message        = ui_log_message,
		set_mouse_cursor   = ui_set_mouse_cursor,
		set_clipboard_text = ui_set_clipboard_text,
		get_clipboard_text = ui_get_clipboard_text,
	}
	state.system_interface = rmlui.rmlui_system_interface_create(&system_callbacks, nil)
	assert(state.system_interface != nil, "RmlUi failed to create the system interface")

	rmlui.rmlui_set_render_interface(state.render_interface)
	rmlui.rmlui_set_system_interface(state.system_interface)
	initialized := rmlui.rmlui_initialise()
	assert(initialized != 0, "RmlUi failed to initialise")
	state.initialized = true

	width, height := platform.get_frame_size(window)
	state.ctx = rmlui.rmlui_context_create(
		UI_CONTEXT_NAME,
		{ i32(width), i32(height) },
		state.render_interface,
	)
	assert(state.ctx != nil, "RmlUi failed to create the main context")

	return state
}

ui_resize :: proc(state: ^UIState, width, height: u32) {
	if state.ctx == nil do return
	rmlui.rmlui_context_set_dimensions(state.ctx, { i32(width), i32(height) })
}

ui_destroy :: proc(state: ^UIState) {
	if state.ctx != nil {
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
}
