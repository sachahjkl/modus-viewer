package viewertool

// The ext/gui_toolkit submodule and the flake's gui_toolkit input are one commit: the window built here is the one that
// the package builds (flake.nix: the package takes the input, a github: flake comes without its submodules;
// src/md/infrastructure/flake.md). socletool has the same check.

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import toolbox "gt:toolbox"

toolkit_pinned :: proc(p: toolbox.Project) -> bool {
	// (the index's commit: the one that the next commit records)
	submodule, code := toolbox.capture({"git", "rev-parse", ":ext/gui_toolkit"})
	if code != 0 {
		fmt.eprintln("viewertool check: the commit of the submodule ext/gui_toolkit cannot be read")
		return false
	}
	text, read_error := os.read_entire_file_from_path("flake.lock", context.temp_allocator)
	if read_error != nil {
		fmt.eprintln("viewertool check: flake.lock cannot be read")
		return false
	}
	lock, parse_error := json.parse_string(string(text), allocator = context.temp_allocator)
	node, _ := lock.(json.Object)["nodes"].(json.Object)["gui_toolkit"].(json.Object)
	revision, _ := node["locked"].(json.Object)["rev"].(json.String)
	if parse_error != nil || string(revision) == "" {
		fmt.eprintln("viewertool check: flake.lock has no gui_toolkit input")
		return false
	}
	if strings.trim_space(submodule) != string(revision) {
		fmt.eprintfln("viewertool check: ext/gui_toolkit is at %s, the flake's gui_toolkit at %s: point both at the same commit", strings.trim_space(submodule), revision)
		return false
	}
	return true
}
