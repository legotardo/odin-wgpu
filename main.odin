package main

import "base:runtime"
import "vendor:wgpu"

import "game"
import "platform"
import "renderer"

state: struct {
	ctx:        runtime.Context,
	window:     platform.Window,
	instance:   wgpu.Instance,
	surface:    wgpu.Surface,
	adapter:    wgpu.Adapter,
	config:     wgpu.SurfaceConfiguration,
	renderer:   renderer.Renderer,
	game_state: game.GameState,
}

main :: proc() {
	state.ctx = context

	state.window = platform.create_window()
	wgpu_init(&state.window)
}
