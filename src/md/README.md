# modus viewer: intent

The viewer shows the screen of a modus machine and sends it the keys and the pointer of the user. It is the native
viewer of the remote display of modus. The design on the side of the system is `src/md/features/remote_display.md` of
the modus repository: the service, the protocol, the authority of a viewer key, and why the viewer is a program of its
own. This folder records the design on the side of the viewer.

## Overview

- Three layers, each with one owner:
  - **The session** (`src/session`): the protocol client. It takes bytes of the stream, checks each record at the
    border of the contract, rebuilds the screen, and gives the bytes that the viewer writes. It is pure: no socket, no
    thread, no window. Its host tests drive it byte by byte.
  - **The connection** (`src/connection`): one thread for each connection. It owns a UDP socket, the QUIC connection
    of modus, and a session. It publishes each whole viewer frame into a picture that it shares with the window.
  - **The window** (`src/`): the form, the screen, the pointer, the input, the sentence of the end. It never waits on
    the disk or the network.
- The viewer reuses the code of the system: the contract `remote_display`, the QUIC and TLS of `modus:support/quic`,
  and the cryptography module compiled for the host. The tool of modus already runs that code on a host in its peer.

## Subtleties

- **A whole viewer frame, or nothing.** The window shows the screen of the last whole viewer frame. A frame in
  progress changes the screen of the session, never the picture that the window shows.
- **The take is at once.** The session queues `Viewer_Frame_Taken` when the frame is whole, before the window draws
  it. The service then sends the next frame while the window uploads this one: the viewer adds no round trip.
- **The pointer is apart.** The machine sends the place of its pointer, not its picture. The viewer draws a mark at
  that place, over the screen.
- **The input is a choice of the user.** The viewer cannot know whether the principal allowed its key for the input.
  The user turns the input on. If the key holds the view alone, the machine ends the session with the code
  `Input_Not_Allowed`, and the sentence of the end says so.
- **The viewer refuses what it must not send.** Each key and each pointer crosses the border of the viewer direction
  before it goes. A pointer outside the screen, or a key code that the contract does not name, stays in the viewer.

## File Index

- [features/session.md](features/session.md): the protocol client; the order of the records, the refusals, the damage
  of a viewer frame, the bytes that the viewer writes
- [features/connection.md](features/connection.md): the thread of a connection; the socket, the wait, the wake, the
  picture shared with the window, the end of a connection and its sentence
- [features/viewer_key.md](features/viewer_key.md): the viewer key; where it is kept, and what the viewer does when the
  store of secrets is absent
- [features/window.md](features/window.md): the form, the screen scaled to the window, the pointer mark, the keys and
  the pointer that go to the machine
- [features/test_machine.md](features/test_machine.md): the command that connects the viewer to a test machine of
  modus, and what `modustool run --remote-display` gives for it
- [features/screenshot.md](features/screenshot.md): the run with no window that writes the picture of the window once
  the first whole screen of the machine is drawn; its condition, its bound and its failures
- [infrastructure/modus_source.md](infrastructure/modus_source.md): how the viewer takes the source of modus, which
  packages build on a host, and which do not
