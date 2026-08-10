package main

import "core:strings"
import "core:os"
import "core:fmt"

ROOT :: "."
RMLUI_ROOT :: "libs/rml-ui"
OUTPUT_DIR :: "build/"

main :: proc() {
    command := "build"
	if len(os.args) > 1 {
		command = os.args[1]
	}

    if command == "run" {
        run_command({
            "odin",
            "run",
            "src",
            "-out:build/game.exe",
        })
        return
    }

    fmt.printf("Starting builder...\n")

    if ODIN_OS == .Windows {
        build_windows()
    } else {
        fmt.eprint("Platform not suported yet")
    }
}

@(private="file")
build_windows :: proc() {
    defer free_all(context.temp_allocator)

    run_command({"git", "submodule", "update", "--init", "--recursive"})

    VCPKG_ROOT := os.get_env("VCPKG_ROOT", context.temp_allocator)
    CMAKE_BIN := os.get_env("CMAKE_BIN", context.temp_allocator)

    if len(VCPKG_ROOT) == 0 || len(CMAKE_BIN) == 0 {
		fmt.eprintln("Missing envs, check the build script to see whats missing")
		os.exit(1)
    }

    toolchain := fmt.tprintf("%s/scripts/buildsystems/vcpkg.cmake", VCPKG_ROOT)
    toolchain_arg := fmt.tprintf("-DCMAKE_TOOLCHAIN_FILE=%s", toolchain)

    run_command({
        CMAKE_BIN,
        "--fresh",
        "--preset", "odin",
        toolchain_arg,
        "-DVCPKG_TARGET_TRIPLET=x64-windows",
    }, RMLUI_ROOT)

    run_command({
        CMAKE_BIN,
        "--build",
        "--preset", "odin",
    }, RMLUI_ROOT)

    rmlui_release := RMLUI_ROOT + "/out/build/odin/Release/"
    rmlui_odin_binding := RMLUI_ROOT + "/Bindings/Odin/rmlui"

    copy_file(rmlui_release, "brotlicommon.dll", OUTPUT_DIR)
    copy_file(rmlui_release, "brotlidec.dll", OUTPUT_DIR)
    copy_file(rmlui_release, "bz2.dll", OUTPUT_DIR)
    copy_file(rmlui_release, "freetype.dll", OUTPUT_DIR)
    copy_file(rmlui_release, "libpng16.dll", OUTPUT_DIR)
    copy_file(rmlui_release, "rmlui_c.dll", OUTPUT_DIR)
    copy_file(rmlui_release, "rmlui.dll", OUTPUT_DIR)
    copy_file(rmlui_release, "z.dll", OUTPUT_DIR)
}

@(private="file")
copy_file :: proc(source_dir, filename, destination_dir: string) {
    source := strings.concatenate({source_dir, filename}, context.temp_allocator)
    destination := strings.concatenate({destination_dir, filename}, context.temp_allocator)

    if !os.is_dir(destination_dir) {
        os.mkdir(destination_dir)
    }

    err := os.copy_file(destination, source)
    if err != nil {
        fmt.eprintln(err)
        os.exit(1)
    }
}

@(private="file")
run_command :: proc(command: []string, working_dir := ROOT) {
    fmt.printf("Running command: %s\n", strings.join(command, " "))

	state, stdout, stderr, err := os.process_exec(
		{
			working_dir = working_dir,
			command = command,
		},
		context.temp_allocator,
	)
	if len(stdout) > 0 {
		fmt.print(string(stdout))
	}
	if len(stderr) > 0 {
		fmt.eprint(string(stderr))
	}
	if err != nil || !state.exited || state.exit_code != 0 {
		fmt.eprintln("Command failed: ", command, err)
		os.exit(1)
	}
}
