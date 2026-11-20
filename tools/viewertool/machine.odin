package viewertool

// `machine <port> <machine key> [--screenshot <file.png>]`: the viewer on a test machine of modus that runs on this
// computer (src/md/features/test_machine.md). The tool of modus relays a port of the loopback to the machine; the
// viewer gets that port, the key that remote_display wrote on the log of the machine, and the input on. With
// --screenshot, the viewer runs with no window, writes the picture of its window once the first whole screen of the
// machine is drawn, and ends (src/md/features/screenshot.md).

import "core:fmt"
import "core:strconv"
import cli "gt:cli"
import toolbox "gt:toolbox"

MACHINE_USAGE :: "viewertool machine <port> <machine key> [--screenshot <file.png>]"

run_machine :: proc(args: []string) -> cli.Exit {
	screenshot := ""
	switch {
	case len(args) == 2:
	case len(args) == 4 && args[2] == "--screenshot" && args[3] != "":
		screenshot = args[3]
	case:
		fmt.eprintfln("usage: %s", MACHINE_USAGE)
		return .Usage
	}
	port, key := args[0], args[1]
	if value, ok := strconv.parse_uint(port, 10); !ok || value == 0 || value > 65535 {
		fmt.eprintfln("viewertool machine: the port %q is not a number from 1 to 65535: give the port of the relay that the tool of modus prints", port)
		return .Usage
	}
	if len(key) != 64 {
		fmt.eprintfln("viewertool machine: the machine key has %d characters, not 64: give the line `remote_display: the public key of this service: <key>` of the log of the machine", len(key))
		return .Usage
	}
	if !toolbox.program_build(build_options()) {
		return .Failed
	}
	command := make([dynamic]string, context.temp_allocator)
	append(&command, PROGRAM, fmt.tprintf("-address:127.0.0.1:%s", port), fmt.tprintf("-machine-key:%s", key), "-input")
	if screenshot != "" {
		append(&command, "-headless", fmt.tprintf("-screenshot:%s", screenshot))
	}
	if !toolbox.run(command[:], {echo = true}) {
		return .Failed
	}
	return .Done
}
