package platform

import "../input"

WindowResizeCall :: #type proc(width, height: u32)
WindowKeyCall :: #type proc(key: input.Key, down: bool)
WindowCursorCall :: #type proc(x, y: f32)
WindowUpdate :: #type proc(dt: f32)
WindowFinish :: #type proc()

WatchFileProc :: #type proc(data: rawptr)
WatchFileHandle :: distinct int
WATCH_FILE_INVALID :: WatchFileHandle(-1)
