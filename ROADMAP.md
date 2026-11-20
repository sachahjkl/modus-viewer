# Roadmap

## Now

- **A window that builds.** The window imports gui_toolkit, whose render package hashes with `core:crypto`, and QUIC
  of modus, whose copy of that cryptography has the same package names; one program cannot hold both. One side must
  change before the viewer opens. [Design](src/md/infrastructure/modus_source.md)

- **A machine of `modustool run` in one command.** `viewertool machine` reaches the machine once the peer of
  `modustool run` relays a port of the loopback to the UDP port 7101 of `remote_display` and prints that port. The
  relay is a change of the modus repository. [Design](src/md/features/test_machine.md)

## Next

- **The connection tested on the host.** A test runs a QUIC server with the protocol of the service in the same
  process, and checks each end code of a session, with no machine.
- **Characters with no key.** A character that the keyboard types with no key of the toolkit (an input method, a dead
  key) goes to the machine with the code of a key that the machine accepts.

## Later

- **A resize of a screen of memory.** A viewer with the input asks the machine for the size of its window.
- **The clipboard.** A paste in the viewer is a paste of the principal on the machine, and a copy on the machine that
  came from the viewer comes back.
- **A record of the screen.** The viewer keeps the stream that it receives as a film, with the encoders of the toolkit.
- **macOS.** The packages of modus that the viewer takes build on an ARM64 processor when their entropy code has a file
  for each processor.
