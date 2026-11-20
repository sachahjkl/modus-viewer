// viewertool: the automation of the project, one program on each system.
//
//   odin run tools/viewertool -collection:gt=ext/gui_toolkit/src -out:build/viewertool -- <command>
//   (build.sh and build.bat are its shortcuts for `build`)
//
// It needs on the path: git, odin, cargo (the native text library of the toolkit on Linux). MODUS_SOURCE names the root
// of the modus source; `nix develop` sets it (src/md/infrastructure/modus_source.md).
package viewertool

import "core:fmt"
import "core:os"
import tk_changelog "gt:changelog"
import toolbox "gt:toolbox"

when ODIN_OS == .Windows {
	PROGRAM :: "build/modus-viewer.exe"
} else {
	PROGRAM :: "build/modus-viewer"
}

DESCRIPTION :: "See and drive the screen of a distant machine, under a key that its owner allows."

// The variable that names the root of the modus source.
MODUS_SOURCE_VARIABLE :: "MODUS_SOURCE"

// The commands that compile nothing: they run with no modus source.
@(rodata)
COMMANDS_WITHOUT_MODUS := [?]string{"help", "-h", "--help", "changelog"}

// What a build on Linux needs: the native text backend of the toolkit.
@(rodata)
LINUX_DEFINES := [?]string{"-define:FONT_BACKEND=native"}

// The packages with host tests. The session needs no window and no socket, so the flake check runs its tests too.
@(rodata)
TESTS := [?]toolbox.Test_Package{{path = "src/session"}}

// The collection of the modus source. Project keeps a slice of it for the life of the tool, so it is a package array.
modus_collection: [1][2]string

// The include folder of the assembler: the host form of the runtime of modus includes `src/runtime/memory.asm`
// from the root of the modus source, and nasm looks for an include in the folders of -i, not next to the file.
modus_assembler_flags: [1]string

project :: proc() -> toolbox.Project {
	return {
		name = "modus-viewer", changelog = "CHANGELOG.md",
		version_file = "src/main.odin", version_line = "APP_VERSION :: ", program = PROGRAM,
		collections = modus_collection[:],
		defines = modus_assembler_flags[:],
		linux_defines = LINUX_DEFINES[:],
		title = "modus viewer", description = DESCRIPTION,
		copyright = "Copyright (c) 2026 sachahjkl",
	}
}

build_options :: proc() -> toolbox.Build_Options {
	p := project()
	return {project = p, changelog_command = tk_changelog.command(p), tests = TESTS[:], tool = "tools/viewertool"}
}

main :: proc() {
	modus := os.get_env(MODUS_SOURCE_VARIABLE, context.allocator)
	if modus == "" && !command_runs_without_modus() {
		fmt.eprintfln("viewertool: %s is empty: run `nix develop` first, or set it to the root of a modus checkout", MODUS_SOURCE_VARIABLE)
		os.exit(2)
	}
	modus_collection[0] = {"modus", fmt.aprintf("%s/src/library", modus)}
	modus_assembler_flags[0] = fmt.aprintf("-extra-assembler-flags:-i%s/", modus)
	p := project()
	b := toolbox.build_commands(build_options())
	toolbox.tool_main("viewertool", {
		b[0], b[1], b[2],
		// (not checked by the toolbox: --screenshot takes its value as the next argument, which run_machine reads)
		{name = "machine", usage = "<port> <machine key> [--screenshot <file.png>]: build the viewer, then connect it to a test machine of modus at 127.0.0.1:<port>, with the input on; with --screenshot, no window: the picture of the window once the first whole screen is drawn (src/md/features/test_machine.md)", run = run_machine},
		tk_changelog.command(p),
	}, toolbox.ROOT_MARK_DEFAULT)
}

@(private = "file")
command_runs_without_modus :: proc() -> bool {
	if len(os.args) < 2 { return true }
	for name in COMMANDS_WITHOUT_MODUS {
		if os.args[1] == name { return true }
	}
	return false
}
