package platform

import "../input"

WindowResizeCall :: #type proc(width, height: u32)
WindowKeyCall :: #type proc(key: input.Key, down: bool)
WindowCursorCall :: #type proc(x, y: f32)
WindowUpdate :: #type proc(dt: f32)
WindowFinish :: #type proc()
