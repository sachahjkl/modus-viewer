# The connection

`src/connection` runs one connection to the service `remote_display` on a thread of its own. The window starts it,
gives it the input, and reads what it publishes. The window never waits for it.

## The thread

1. It resolves the address (a name can need a DNS query), and opens one UDP socket.
2. It starts a QUIC client of `modus:support/quic`, with the viewer key, the pinned key of the machine and the
   application protocol `modus-remote-display`.
3. When the handshake completes, it opens the one bidirectional stream and drives the session: the bytes that the
   session writes go to the stream, the bytes of the stream go to the session.
4. When a viewer frame is whole, it copies the damage into the picture that it shares with the window, as RGBA, and
   wakes the window.
5. When QUIC closes, it writes the end and wakes the window.

## The wait

The thread waits on its socket with a receive timeout: the time to the next deadline of QUIC, at least 1 ms and at most
one second. Two things end the wait early:

- a datagram of the machine;
- a wake of the window: one byte from a second socket of the connection to the loopback port of the first one. The
  window sends it after it queues a key or a pointer, or asks for the end. The thread drops a datagram from any other
  sender.

So a key goes at once, and the thread wakes for no timer of its own. A plain receive timeout of a few milliseconds was
refused: it delays each key by up to that time, and wakes the thread hundreds of times a second at rest.

## The shared picture

The connection and the window share one record under a lock: the RGBA pixels of the screen (at most 1920 x 1080), the
screen size, the damage since the window last took it, the place of the pointer, the count of frames, and the end.

- The thread holds the lock only to copy the damage of one frame, and to write the end.
- The window holds it only to upload the damage to its texture, and to read the end.
- The damage of the shared record has a capacity. Past it, the rectangles join into their bounding rectangle.

## The end

The end is one value, `session.End`, with one kind and its code. `session.end_sentence` gives its sentence, with the
code, for the window. The kinds:

| Kind | When |
|---|---|
| `Closed_By_Viewer` | The user ended the session |
| `Machine_Code` | The machine closed with an application code of the contract: `Revoked`, `Timeout`, `Input_Not_Allowed`, ... |
| `Viewer_Refused_Record` | The session refused a record of the machine; the viewer closed with `Bad_Record` |
| `Key_Not_Allowed` | The machine refused the viewer key in the handshake (`access_denied`) |
| `Machine_Key_Differs` | The key of the machine is not the pinned key (`bad_certificate`) |
| `No_Handshake` | The handshake did not end before its deadline: no machine answered, or the service holds two viewers |
| `Machine_Silent` | The idle timeout of QUIC ended the connection |
| `Transport_Code` | Another transport code, of either side |
| `Address_Not_Found` | The name of the host did not resolve |
| `No_Socket` | The system gave no UDP socket |
| `Start_Refused` | The QUIC client did not start |
