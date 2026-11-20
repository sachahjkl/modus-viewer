# The session: the protocol client

`src/session` is the client of the protocol of `remote_display`: the stream of one connection, seen from the viewer.
It is pure. It takes the bytes that QUIC gives, and gives the bytes that QUIC must send. The connection thread drives
it; the host tests drive it with no socket.

## The phases

One enum, `Phase`, holds where the session is. Each record moves it by one rule.

```
Before_Screen_Size --Screen_Size--> Between_Frames --Viewer_Frame_Start--> In_Frame
                                         ^  |                                 |
                                         |  +--Screen_Size, Pointer_Place     |
                                         +-------Viewer_Frame_End-------------+
any phase --a refused record--> Refused (the last phase)
```

- `Screen_Size` in `In_Frame` is refused: a frame shows one moment of one screen.
- A second `Screen_Size` between frames is a new size (the screen of memory of a later layer). The session takes it,
  and the next frame must be the whole screen. The session does not check that: the service owes it.
- `Pointer_Place` is taken in every phase but `Before_Screen_Size`: the border refuses a place outside a screen of
  zero pixels.
- `Viewer_Frame_Start` must have the serial of the last frame plus one, from 1: the contract says so, and a skipped
  serial means a lost frame.
- A screen piece must be in a frame, within the count and the bytes that its `Viewer_Frame_Start` gave.
- `Viewer_Frame_End` must name the serial of the frame, after its last screen piece.

A refusal is final: the connection closes with the code `Bad_Record`, as the peer of the modus tool does. The session
keeps why: a `Record_Problem` of the contract, a `Screen_Piece_Problem` of the decoder, or a `Refusal` of the order.

## The read

The session reads one record at a time. `session_receive_space` gives the bytes that the session wants next: the rest
of the header, then the rest of the body. The connection reads at most that many bytes from the stream, so a header
past its bound is refused before any byte of its body is read. `session_received` counts them, and acts when the record
is whole. `session_receive` does both from a slice, for a caller that has the bytes already, such as a test.

## The screen and the damage

The session keeps the screen that it rebuilds, `0x00RRGGBB` pixels with the stride of the screen width. A screen piece
decodes first into memory of its own: a damaged piece changes no pixel of the screen.

Each frame keeps its damage: the rectangles that its screen pieces covered, at most `DAMAGE_CAPACITY`. A piece that
extends a rectangle on its row or its column joins it. Past the capacity, all the rectangles join into their bounding
rectangle: the window then uploads more pixels, never fewer. When the frame is whole, the caller reads the damage, then
gives the session more bytes. The next `Viewer_Frame_Start` clears it.

## The write

The session holds the bytes that the viewer writes, in order: `Session_Start` first, then `Viewer_Frame_Taken` of each
whole frame, the keys and the pointer records.

- `Viewer_Frame_Taken` always has room. A key or a pointer is refused when it would take the room of the next one.
- A key and a pointer cross `viewer_record_check` of the contract before they go. A record that the border of the
  service would refuse stays in the viewer.
- A pointer record that waits at the end of the bytes, with the same buttons and no wheel, takes the place of the new
  one: a fast move of the mouse sends the last place, not each place.
- With the input off, the session refuses each key and each pointer.

## The refused forms

- **A session that reads from the socket itself.** The tests then need a socket, and the order of the records mixes
  with the timing of the network.
- **A copy of the screen per frame.** The window reads the damage of the last whole frame from the screen of the
  session, before the next bytes. A second copy costs 8 MB for nothing.
