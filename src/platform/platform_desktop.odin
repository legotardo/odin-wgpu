#+build !js
package platform

import "core:os"
import "../input"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:time"
import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

Window :: struct {
	ctx:             runtime.Context,
	width:           u32,
	height:          u32,
	handle:          glfw.WindowHandle,
	resize_callback: WindowResizeCall,
	key_callback:    WindowKeyCall,
	cursor_callback: WindowCursorCall,
	terminate:       bool,
}

create_window :: proc() -> Window {
	glfw.SetErrorCallback(error_callback)

	if ODIN_OS == .Linux {
		glfw.InitHint(glfw.PLATFORM, glfw.PLATFORM_X11)
	}

	intialized := glfw.Init()
	assert(intialized == true, "GLFW failed to init")

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	handle := glfw.CreateWindow(1920, 1080, "Odin :)", nil, nil)
	assert(handle != nil, "Failed to create a GLFW Window")

	glfw.SetFramebufferSizeCallback(handle, framebuffer_callback)
	glfw.SetKeyCallback(handle, key_callback)
	glfw.SetCursorPosCallback(handle, cursor_pos_callback)

	glfw.SetInputMode(handle, glfw.CURSOR, glfw.CURSOR_DISABLED)

	if glfw.RawMouseMotionSupported() {
		glfw.SetInputMode(handle, glfw.RAW_MOUSE_MOTION, 1)
	}

	return {width = 800, height = 600, handle = handle}
}

// TODO: Find a better way to do this
prepare_context :: proc(window: ^Window) {
	glfw.SetWindowUserPointer(window.handle, window)
}

toggle_cursor :: proc(window: ^Window) {
	current_mode := glfw.GetInputMode(window.handle, glfw.CURSOR)

	if (current_mode == glfw.CURSOR_DISABLED) {
		glfw.SetInputMode(window.handle, glfw.CURSOR, glfw.CURSOR_NORMAL)
	} else {
		glfw.SetInputMode(window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
	}
}

should_close :: proc(window: ^Window) -> bool {
	return glfw.WindowShouldClose(window.handle) == true || window.terminate
}

pool_events :: proc(window: ^Window) {
	glfw.PollEvents()
}

destroy_window :: proc(window: ^Window) {
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

get_window_proc :: proc(window: ^Window) -> rawptr {
	return window.handle
}

get_window_surface :: proc(window: ^Window, instance: wgpu.Instance) -> wgpu.Surface {
	return glfwglue.GetSurface(instance, window.handle)
}

get_frame_size :: proc(window: ^Window) -> (width, height: u32) {
	iw, ih := glfw.GetFramebufferSize(window.handle)

	return u32(iw), u32(ih)
}

get_dpi :: proc(window: ^Window) -> f32 {
	sw, sh := glfw.GetWindowContentScale(window.handle)
	return sw
}

run :: proc(window: ^Window, update_callback: WindowUpdate, finish_callback: WindowFinish) {
	dt: f32

	for !should_close(window) {
		start := time.tick_now()

		pool_events(window)
		update_callback(dt)
		dt = f32(time.duration_seconds(time.tick_since(start)))
	}

	finish_callback()
}

@(private)
framebuffer_callback :: proc "c" (handle: glfw.WindowHandle, width, height: c.int) {
	ptr := cast(^Window)glfw.GetWindowUserPointer(handle)

	if ptr == nil {
		return
	}

	if ptr.resize_callback != nil {
		context = ptr.ctx
		ptr.resize_callback(u32(width), u32(height))
	}

	ptr.width = u32(width)
	ptr.height = u32(height)
}

@(private)
error_callback :: proc "c" (code: c.int, description: cstring) {
	context = runtime.default_context()
	fmt.printf("GLFW Error %v: %s\n", code, description)
}

@(private = "file")
key_from_glfw :: proc(key: c.int) -> input.Key {
	switch key {
	case glfw.KEY_W:
		return .W
	case glfw.KEY_S:
		return .S
	case glfw.KEY_A:
		return .A
	case glfw.KEY_D:
		return .D
	case glfw.KEY_P:
		return .P
	case glfw.KEY_F:
		return .F
	case glfw.KEY_SPACE:
		return .Space
	case glfw.KEY_LEFT_ALT:
		return .LeftAlt
	case glfw.KEY_LEFT_SHIFT:
		return .LeftShift
	case glfw.KEY_ESCAPE:
		return .Escape
	case glfw.KEY_EQUAL:
		return .Equal
	case glfw.KEY_MINUS:
		return .Minus
	case glfw.KEY_L:
		return .L
	case:
		return .Unkown
	}
}

@(private)
key_callback :: proc "c" (handle: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	ptr := cast(^Window)glfw.GetWindowUserPointer(handle)

	if ptr == nil {
		return
	}

	if ptr.resize_callback != nil {
		context = ptr.ctx

		key := key_from_glfw(key)

		ptr.key_callback(key, action == glfw.PRESS || action == glfw.REPEAT)
	}
}

@(private)
cursor_pos_callback :: proc "c" (handle: glfw.WindowHandle, xpos, ypos: f64) {
	ptr := cast(^Window)glfw.GetWindowUserPointer(handle)

	if ptr == nil {
		return
	}

	if ptr.cursor_callback != nil {
		context = ptr.ctx

		ptr.cursor_callback(f32(xpos), f32(ypos))
	}
}

get_num_cores :: proc() -> int {
    return os.get_processor_core_count()
}

WatchFileProc :: #type proc(data: rawptr)

WatchFile :: struct {
	path: string,
	time: time.Time,
	call: WatchFileProc,
	data: rawptr,
}

watch_files: [dynamic]WatchFile

watch_file_init :: proc() {
	if !ODIN_DEBUG do return

	watch_files = make([dynamic]WatchFile)
}

watch_file :: proc(path: string, call: WatchFileProc, data: rawptr) {
	if !ODIN_DEBUG do return

    append(&watch_files, WatchFile{
        path = path,
        time = {},
        call = call,
		data = data,
    })
}

WATCH_FILE_INTERVAL :: 1.0 / 20
watch_file_accumulator: f32 = 0.0
watch_file_update :: proc() {
	if !ODIN_DEBUG do return

	for &file in watch_files {
		last_info, err := os.stat(file.path, context.temp_allocator)
		if err != os.ERROR_NONE {
			fmt.eprintf("Error reading file info:", err)
			return
		}

		curr_mtime := last_info.modification_time
		os.file_info_delete(last_info, context.temp_allocator)

		if file.time._nsec == 0 {
			file.time = curr_mtime
			continue
		}

		if curr_mtime != file.time {
			file.time = curr_mtime
			file.call(file.data)
		}
	}
}
