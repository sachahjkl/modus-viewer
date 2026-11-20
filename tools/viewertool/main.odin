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
import cli "gt:cli"
import release "gt:release"
import toolbox "gt:toolbox"
import viewer_update "../../src/update"

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
COMMANDS_WITHOUT_MODUS := [?]string{"help", "-h", "--help", "changelog", "i18n", "update", "notes"}

// What a build on Linux needs: the native text backend of the toolkit.
@(rodata)
LINUX_DEFINES := [?]string{"-define:FONT_BACKEND=native"}

// The packages with host tests. The session needs no window and no socket, so the flake check runs its tests too.
@(rodata)
TESTS := [?]toolbox.Test_Package{{path = "src/session"}, {path = "src/layout"}}

// What the French reader sees: the texts of the viewer, from its code, into i18n/<language>.txt (the program embeds
// them). `viewertool i18n fr` writes the catalogue; `check` compares it with the code.
I18N := toolbox.I18n_Catalogues{dirs = {"src"}, folder = "i18n"}

// What goes beside the program in the archive of a release.
@(rodata)
DIST_FILES := [?][2]string{{"README.md", "README.md"}, {"LICENSE", "LICENSE"}, {"CHANGELOG.md", "CHANGELOG.md"}}

// The collection of the modus source. Project keeps a slice of it for the life of the tool, so it is a package array.
modus_collection: [1][2]string

// The variable of the default options of nasm. The host form of the runtime of modus includes
// `src/runtime/memory.asm` from the root of the modus source, and nasm looks for an include in the folders of -i, not
// next to the file. The tool gives that folder through the environment of its children: `odin check` refuses
// -extra-assembler-flags, and every odin command of the toolbox gets the same flags.
NASM_OPTIONS_VARIABLE :: "NASMENV"

project :: proc() -> toolbox.Project {
	return {
		name = "modus-viewer", repository = "https://github.com/sachahjkl/modus-viewer", changelog = "CHANGELOG.md",
		version_file = "src/main.odin", version_line = "APP_VERSION :: ", program = PROGRAM,
		collections = modus_collection[:],
		// (not macOS: the entropy code of modus is x86 only, src/md/infrastructure/modus_source.md)
		systems = {.Linux, .Windows},
		linux_defines = LINUX_DEFINES[:],
		title = "modus viewer", description = DESCRIPTION,
		copyright = "Copyright (c) 2026 sachahjkl",
	}
}

build_options :: proc() -> toolbox.Build_Options {
	p := project()
	return {project = p, changelog_command = tk_changelog.command(p), tests = TESTS[:], tool = "tools/viewertool", catalogues = I18N}
}

main :: proc() {
	modus := os.get_env(MODUS_SOURCE_VARIABLE, context.allocator)
	if modus == "" && !command_runs_without_modus() {
		fmt.eprintfln("viewertool: %s is empty: run `nix develop` first, or set it to the root of a modus checkout", MODUS_SOURCE_VARIABLE)
		os.exit(2)
	}
	modus_collection[0] = {"modus", fmt.aprintf("%s/src/library", modus)}
	if modus != "" {
		_ = os.set_env(NASM_OPTIONS_VARIABLE, fmt.tprintf("-i%s/", modus))
	}
	p := project()
	b := toolbox.build_commands(build_options())
	// (the release: the program alone and its manifest signed by $UPDATE_SIGNING_KEY, what an installed copy updates from)
	r := release.commands({project = p, dist = "build/dist", files = DIST_FILES[:], check = proc() -> cli.Exit { return toolbox.ended(toolbox.program_check(build_options())) }, update = viewer_update.PRODUCT})
	toolbox.tool_main("viewertool", {
		b[0], b[1], b[2],
		r[0], r[1], r[2],
		toolbox.i18n_command(I18N),
		{name = "update", usage = "keygen <file> | pubkey | manifest <program> <version> - <out> | verify <manifest> -: the update key of the viewer and its manifests", run = proc(args: []string) -> cli.Exit { return toolbox.update_command(viewer_update.PRODUCT, args) }},
		// (not checked by the toolbox: --screenshot takes its value as the next argument, which run_machine reads)
		{name = "machine", usage = "<port> <machine key> [--screenshot <file.png> [--bar]] [--measure]: build the viewer, then connect it to a test machine of modus at 127.0.0.1:<port>, with the input on; with --screenshot, no window: the picture of the window once the first whole screen is drawn, with the floating bar for --bar; --measure prints the measures at the end (src/md/features/test_machine.md)", run = run_machine},
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
