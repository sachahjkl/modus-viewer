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

The thread waits on its socket with a receive timeout: the time to the next deadline of QUIC, with a bound.

- A datagram of the machine ends the wait at once. The thread drops a datagram from any other sender.
- The window puts keys, pointer records and the request of the end in a queue under the lock, and makes no system call.
  The thread reads the queue after each wait.
- So the bound of a wait is the delay of a key: `INPUT_WAIT_BOUND` (4 ms) while the machine holds the input,
  `IDLE_WAIT_BOUND` (100 ms) else, which is the delay of a Disconnect. The window switches the hold with
  `connection_hold_input` (Ctrl+Alt, the switch of the bar).
- After each turn, the thread publishes the smoothed round trip of QUIC and its loss (two probes in a row with no
  acknowledgement), and keeps each new sample of the round trip for `-measure`. It wakes the window only when the
  round trip changes by a whole millisecond or the loss changes.

A wake datagram from the window to the loopback port of the thread was refused: it is a system call on the interface
thread, which never makes one. The cost of the bound is up to 250 wakes of the thread a second while the input is on,
and 10 at rest.

## The shared picture

The connection and the window share one record under a lock: the RGBA pixels of the screen (at most 1920 x 1080), the
screen size, the damage since the window last took it, the place of the pointer, the count of frames, and the end.

- The thread holds the lock to convert the damage of one frame to RGBA, and to write the end. A whole screen is about
  2 million pixels: the window can wait that long for the lock, once, at the first frame.
- The window holds it only to upload the damage to its texture, and to read the end.
- The thread wakes the window with a post of the toolkit (`ui.post`), never by a call into the window.
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
| `No_System_Random` | The generator of the operating system gave no seed for the random generator of QUIC |
| `Start_Refused` | The QUIC client did not start |
