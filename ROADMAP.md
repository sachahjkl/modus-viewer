# Roadmap

## Now

- **The window.** The viewer shows the screen of the machine at its size, draws the pointer apart, sends the keys and
  the pointer when the user turns the input on, and says why each connection ended.
  [Design](src/md/features/window.md)
- **A test machine of modus in one command.** `viewertool machine` connects the viewer to a machine that the tool of
  modus runs on this computer. It needs a relay of the UDP port of the remote display in that tool.
  [Design](src/md/features/test_machine.md)

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
