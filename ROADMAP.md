# Roadmap

## Now

## Next

- **The shape of the pointer, the warps and the round trip of an input.** With version 2 of the protocol of modus, the
  cursor takes the shape that the machine names, follows the moves that the machine makes itself, and `-measure` and
  the bar give the time from an input to the frame that shows it. [Design](src/md/features/immediacy.md)
- **Crisp pixels at a whole scale above 1.** The screen at 2:1 shows each pixel of the machine as a sharp block, once
  `gt:draw` of gui_toolkit draws an image with nearest sampling. [Design](src/md/features/interface.md)
- **The host pointer moved by a warp.** A warp of the machine moves the host pointer, once `gt:platform` can move it;
  until then the viewer keeps an offset. [Design](src/md/features/immediacy.md)
- **Motions as QUIC datagrams.** A lost motion is never sent again, once `modus:support/quic` has the DATAGRAM frame;
  keys and buttons stay on the stream. [Design](src/md/features/immediacy.md)

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
