# What makes the remote immediate

The rules of the good remote desktop clients (RDP, Parsec, Moonlight, SPICE): the pointer never waits for the
machine, an input never waits behind a picture, a picture never waits in a queue, and each claim has a number.

## The cursor

- **The local cursor is the host cursor.** While the input is held and the pointer is over the screen, the cursor is
  the cursor of the host system, moved by the system at its own rate: no frame of the viewer and no frame of the
  machine is on its path. The screen box sets the cursor of the window to the shape that the machine names.
- **The screen pieces hold no pointer.** The compositor of modus copies the screen before it draws its pointer
  (design of the remote display in modus, "The pointer stays out of the pixels"). So the local cursor never shows a
  second, late pointer under it.
- **The shape.** Protocol version 1 sends no shape: the cursor is the arrow of the host. Version 2 names the shape of
  the pointer theme of modus (`pointer_pictures.Pointer_Shape`: arrow, text, pointing hand, move, grab, the resizes,
  …). The viewer then takes the host cursor of the same kind when the host has one, else the picture that the machine
  sends once for that shape, as a custom cursor of the platform.
- **The machine pointer when the input is released.** The cursor is the host's again, and the machine's pointer is
  drawn over the screen at the place of its last `Pointer_Place`, as an arrow that the viewer draws once into a
  texture (`src/cursor_arrow.odin`). The headless screenshot shows it the same way: it has no host cursor.
- **Reconciliation.** The viewer's cursor is the truth for motion. While the input is held, a `Pointer_Place` of
  version 1 is not drawn: it only follows the motions of the viewer, one round trip late. Version 2 adds
  `Pointer_Warp`, sent only when the machine moves the pointer itself (a warp, a drag that it constrains). A warp moves
  the cursor of the viewer: the viewer moves the host pointer when the platform allows it, else it keeps an offset
  between the host pointer and the pointer of the machine until the next release of the input. `gt:platform` has no
  warp of the host pointer yet: the offset is the first form.

## The input path

- **Motions are coalesced to one for each frame of the host.** The window reads its events once for each frame, at
  the rate of the display. It keeps the last motion of the batch only, and sends it at the end of the batch: a fast
  mouse sends its newest place, never a queue of old ones. The queue of the connection replaces a motion that waits
  with the next one too.
- **Buttons, wheels and keys are never coalesced and never reordered.** Before a button, a wheel notch or a key, the
  motion that waits is sent first, so the machine sees the press at the place where it happened.
- **The transport: the input direction of the one QUIC stream.** QUIC controls the flow of each direction alone, and
  the viewer sends only input in its direction: an input never waits behind screen data. A lost packet of input delays
  the input after it, which is what keys and buttons need: their order is their meaning. Unreliable QUIC datagrams
  (RFC 9221) would let a motion skip a lost one, since only the newest place matters; `modus:support/quic` has no
  DATAGRAM frame yet, so motions use the stream. The motion then moves to datagrams, keys and buttons stay on the
  stream.
- **The thread of the connection sends at once** after it takes the queue: it waits at most 4 ms while the input is
  held (`connection.md`, "The wait"). The window makes no system call to wake it.

## The frames

- **One frame in flight, one frame waiting.** The service sends a viewer frame only after the take of the last one.
  The viewer takes each frame as soon as it is whole, before it draws it. The shared picture holds the newest screen:
  a frame that comes before the window took the last one joins it, and is counted as dropped.
- **Presented at the next vsync.** A whole frame wakes the window with a post; the window uploads its damage in the
  next frame, which the pacer of the toolkit presents at the next refresh of the display. No queue of pictures.

## The numbers

- **In the bar:** the round trip of QUIC (its smoothed round trip, the time of a packet to the machine and its
  acknowledgement back), and the frames of the machine that the window presented in the last second. A still screen
  sends no frame: 0 fps is a still screen, not a slow one.
- **`-measure`:** at its end, the viewer prints one line for each measure:
  - the round trip of QUIC: its least and its median sample;
  - the interval between two presented frames of the machine: median and 95th percentile;
  - the frames that came while the window had not taken the last one (dropped), and the frames presented;
  - the round trip of the input: "not measured" with protocol version 1.
- **The round trip of the input, version 2.** `Viewer_Frame_Start` names the count of input records of this viewer
  that the compositor applied before the copy of the frame. The viewer keeps the time at which it sent each record
  (a ring of 256). The first frame whose count covers an input is the first frame that can show its effect: its time
  less the time of the send is the round trip of that input. It is the same tie as the key to the screen of modus (a
  serial, never a time sent back), on the path of a viewer.
- **No claim without its line.** A claim of smoothness quotes the lines of `-measure`.

## What modus needs (the next step)

The records of protocol version 2 are designed in the design of the remote display of modus ("The pointer of a
viewer, and the echo of the input"): `Pointer_Shape`, `Pointer_Picture`, `Pointer_Warp`, and the count of applied
input in `Viewer_Frame_Start`. The viewer of this step uses version 1 only.
