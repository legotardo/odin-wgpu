#+build !js
package platform

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:time"
import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

WindowResizeCall :: #type proc(width, height: u32)
WindowUpdate :: #type proc(dt: f32)
WindowFinish :: #type proc()

Window :: struct {
	ctx:             runtime.Context,
	width:           u32,
	height:          u32,
	handle:          glfw.WindowHandle,
	resize_callback: WindowResizeCall,
}

create_window :: proc() -> Window {
	glfw.SetErrorCallback(error_callback)

	glfw.InitHint(glfw.PLATFORM, glfw.PLATFORM_X11)

	intialized := glfw.Init()
	assert(intialized == true, "GLFW failed to init")

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	handle := glfw.CreateWindow(800, 600, "Odin :)", nil, nil)
	assert(handle != nil, "Failed to create a GLFW Window")

	glfw.SetFramebufferSizeCallback(handle, framebuffer_callback)

	return {width = 800, height = 600, handle = handle}
}

// TODO: Find a better way to do this
prepare_context :: proc(window: ^Window) {
	glfw.SetWindowUserPointer(window.handle, window)
}

should_close :: proc(window: ^Window) -> bool {
	return glfw.WindowShouldClose(window.handle) == true
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
