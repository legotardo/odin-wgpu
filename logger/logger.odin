package logger

import "core:fmt"
import "core:time"

Level :: enum {
	Debug,
	Info,
	Warn,
	Error,
}

log :: proc(level: Level, format: string, args: ..any) {
	now := time.now()
	prefix: string

	switch level {
	case .Debug:
		prefix = "[DEBUG]"
	case .Info:
		prefix = "[INFO]"
	case .Warn:
		prefix = "[WARN]"
	case .Error:
		prefix = "[ERROR]"
	}

	fmt.printf("%v %s ", now, prefix)
	fmt.printf(format, ..args)
	fmt.println()
}

debug :: proc(format: string, args: ..any) {
	log(.Debug, format, ..args)
}

info :: proc(format: string, args: ..any) {
	log(.Info, format, ..args)
}

warn :: proc(format: string, args: ..any) {
	log(.Warn, format, ..args)
}

error :: proc(format: string, args: ..any) {
	log(.Error, format, ..args)
}
