#+build js
package platform

import "base:runtime"
import "core:sys/wasm/js"
import "vendor:wgpu"

Window :: struct {
	ctx:             runtime.Context,
	width:           u32,
	height:          u32,
	handle:          rawptr,
	resize_callback: WindowResizeCall,
	key_callback:    WindowKeyCall,
	cursor_callback: WindowCursorCall,
	terminate:       bool,
}

state: struct {
	window:          ^Window,
	update_callback: WindowUpdate,
	finish_callback: WindowFinish,
	initialized:     bool,
	wgpu_ready:      bool,
}

create_window :: proc() -> Window {
	assert(
		js.add_window_event_listener(.Resize, nil, size_callback),
		"Failed to assign resize callback",
	)

	return {width = 800, height = 600}
}

prepare_context :: proc(window: ^Window) {
	state.wgpu_ready = true
	state.window = window
}

should_close :: proc(window: ^Window) -> bool {
	return !state.initialized
}

pool_events :: proc(window: ^Window) {
}

destroy_window :: proc(window: ^Window) {
}

watch_file_init :: proc() {
}

watch_file :: proc(path: string, call: WatchFileProc, data: rawptr) -> WatchFileHandle {
	return WATCH_FILE_INVALID
}

unwatch_file :: proc(handle: WatchFileHandle) {
}

watch_file_update :: proc() {
}

watch_file_destroy :: proc() {
}

get_window_proc :: proc(window: ^Window) -> rawptr {
	return window.handle
}

toggle_cursor :: proc(window: ^Window) {}

get_dpi :: proc(window: ^Window) -> f32 {
	return 100
}

get_window_surface :: proc(window: ^Window, instance: wgpu.Instance) -> wgpu.Surface {
	return wgpu.InstanceCreateSurface(
		instance,
		&wgpu.SurfaceDescriptor {
			nextInChain = &wgpu.SurfaceSourceCanvasHTMLSelector {
				sType = .SurfaceSourceCanvasHTMLSelector,
				selector = "#wgpu-canvas",
			},
		},
	)
}

get_frame_size :: proc(window: ^Window) -> (width, height: u32) {
	rect := js.get_bounding_client_rect("body")
	dpi := js.device_pixel_ratio()
	return u32(f64(rect.width) * dpi), u32(f64(rect.height) * dpi)
}

run :: proc(window: ^Window, update_callback: WindowUpdate, finish_callback: WindowFinish) {
	state.initialized = true
	state.update_callback = update_callback
	state.finish_callback = finish_callback
}

@(private)
size_callback :: proc(e: js.Event) {
	width, height := get_frame_size(state.window)
	state.window.resize_callback(width, height)
}

@(private = "file", export)
step :: proc(dt: f32) -> bool {
	if !state.initialized || !state.wgpu_ready {
		return true
	}

	state.update_callback(dt)

	return true
}

@(private = "file", fini)
os_fini :: proc "contextless" () {
	context = runtime.default_context()

	state.finish_callback()
}

get_num_cores :: proc() -> int {
    return 1
}
