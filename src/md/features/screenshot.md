# The screenshot

`modus-viewer -address:<host>:<port> -machine-key:<key> -headless -screenshot:<file.png>` connects, writes the
picture of its window once the first whole screen of the machine is drawn, and ends with 0. It shows that the viewer
works, with no person and no window on the desktop. `viewertool machine <port> <key> --screenshot <file.png>` passes
both options.

## No window

`-headless` opens the window with `headless` of `gt:host`: a window of no system, drawn into a picture by the
software renderer of the toolkit. The software renderer gives the same pixels on every machine and needs no graphics
card. `headless_gpu` was not taken: the screenshot is one picture, and a run on the card depends on a driver.

## The condition

The capture starts on a condition, never after a time:

1. The first viewer frame of a session is the whole screen (the design of the remote display in modus, "One viewer
   frame in flight").
2. `connection_changed` uploads it to the texture of the window.
3. `draw_screen` draws the texture, and sets `screen_drawn` when at least one whole frame came.
4. After that frame, the loop asks the renderer for a read back (`render.capture_request`). The next frame is copied,
   and `render.capture_poll` gives its pixels after a frame or more.
5. `gt:png` encodes them, the file is written, and the loop ends. The connection then closes with the code 0, so the
   machine sees the viewer go.

`Screenshot_Phase` holds these steps: `Waiting`, `Capture_Asked`, then `Written` or `Failed`.

## The bound and the failures

- `SCREENSHOT_HANG_BOUND` (120 s, from the start of the viewer) only ends a run that hangs: the viewer key, the
  handshake, the first frame and the read back all fit in it on a working run.
- While it waits, the loop sleeps until a post of the connection or of the key worker wakes the window, and at most
  `SCREENSHOT_CHECK_PERIOD_MILLISECONDS` so that it checks the bound. It asks for no frame of its own: a frame of the
  software renderer is work.
- An end of the connection before the first frame, no viewer key, a refused read back or a file that cannot be written
  ends the viewer with 1 and one sentence on the standard error.
- `-screenshot` needs `-address` and `-machine-key`: the picture is of the session that starts with the viewer.

## The refused forms

- **A delay after the connection.** A slow machine would give a picture of an empty window, and a fast one would wait
  for nothing.
- **A picture of the screen of the machine alone, from the session.** The proof is that the window draws the screen:
  the scale, the bar and the pointer mark are in the picture.
