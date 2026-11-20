# The interface

The window shows the screen of the machine, and nothing else, until the user asks for more. The first picture of the
viewer had a bar of debug facts, bands of 90 px above and under the screen, and a screen shrunk to two thirds. This
file is the interface that replaces it.

## The states of the window

One enum, `View_State`, derived each frame from what the window holds. It is never stored, so it cannot disagree with
the connection.

| State | When | What the window shows |
|---|---|---|
| `Form` | No session was asked yet | The form: the line that allows the viewer key, the address, the machine key, the switch of the input, Connect |
| `Connecting` | A connection runs, and no whole frame came | A centred message on the background of the window: "Connecting to machine 3b0a9b25" |
| `Screen` | A whole frame came | The screen of the machine, alone |
| `Ended` | The last connection ended | A centred message: the sentence of the end with its code, Retry (primary), and Change the address |

Retry starts the same session again: same address, same machine key, same input. Change the address goes back to the
form. A refused key, a lost connection and a revocation all reach `Ended`: the sentence says which.

## The screen fills the window

- **No bar takes room.** The screen box is the whole client area of the window.
- **The scale** (`src/layout/placement.odin`, pure, host-tested):
  - `Fit`, the default: 1:1 when the screen fits; else the largest scale that fits, with the proportions kept.
  - A scale of 1 or more is a whole number: the screen is drawn at 1:1, 2:1, …, never at 1.4:1.
  - A scale under 1 is filtered.
  - `One_To_One`: always 1:1. A screen larger than the window moves with the pointer: the place of the pointer in the
    window is the same share of the screen as of the window, so each pixel of the screen can be reached.
  - The rectangle of the screen starts on a whole pixel, so a pixel of the machine is a pixel of the host at 1:1.
- **The size of the window.** At the first whole frame of a session, a window that the user did not resize and that is
  not in full screen takes the size of the screen of the machine when it fits in 90 % of the monitor, else the largest
  size with its proportions that fits. With no bands, the scale is then 1:1 or a clean fit. A window with no system
  (`-headless`) takes the size of the screen.
- **Nearest pixels at a whole scale above 1.** `gt:draw` samples an image with a filter and has no nearest sampling.
  Until the toolkit has it, a whole scale above 1 is soft. It is in the roadmap of the viewer, as a work of the toolkit.

## Two modes

- **Windowed:** the native decorations of the system, as the other programs of the owner have by default. The title
  names the machine: `machine 3b0a9b25`, the head of its key, as the bar of modus names a viewer. No address is shown:
  an address is a detail of the transport, and the key is what the user trusted.
- **Full screen:** `platform.set_fullscreen`. No title bar; the floating bar is the only way out, with the shortcut.

## The floating bar

A thin bar, centred at the top of the screen area, over the screen. It is not there until the pointer asks for it.

- **The pointer state machine** (`Bar_Hover`), on the place of the host pointer that the window reads from each event,
  with the timing of the toolkit for a strip on hover (`ui.VIEW_HOVER_EDGE_EM`, `ui.VIEW_HOVER_DWELL_MS`):
  - `Hidden` → `Armed` when the pointer enters the top band of the screen area, with no button down.
  - `Armed` → `Shown` after the dwell; `Armed` → `Hidden` when the pointer leaves the band first.
  - `Shown` → `Leaving` when the pointer leaves the bar; `Leaving` → `Shown` when it comes back; `Leaving` →
    `Hidden` after the dwell.
  - Each transition with a time asks the toolkit for a wake at its deadline (`ui.wake_within`): no timer of its own.
- **What it holds**, each fact once:
  - the name of the machine (`machine 3b0a9b25`);
  - the indicator of the connection: a dot and one short text. Green below 50 ms of round trip, yellow from 50 ms,
    red and the word "lost" when QUIC sends its probes with no answer. The text is the round trip and the frames of
    the last second: `12 ms · 60 fps`. Its meaning is in `immediacy.md`;
  - the buttons, with the controls of the toolkit: `1:1` or `Fit` (the button names the other scale), `Full screen` or
    `Window`, the switch `Input`, and `Disconnect`.
- **The pointer over the bar is the window's**: its events reach the interface, never the machine.

## The input

- **The input is held or released.** Held: the keys and the pointer over the screen go to the machine, and only the
  bar and the shortcut stay the window's. Released: the window keeps all of them.
- **Ctrl+Alt switches it.** It is the shortcut of the remote desktop clients that the user knows. Its press is not
  sent; the releases of Ctrl and Alt are sent, so no modifier stays down on the machine. A toast of the toolkit says
  "Input released — Ctrl+Alt to give it back", or "Input given to the machine".
- **Escape goes to the machine**, as every other key: the viewer eats no key of the machine.
- **The switch `Input` of the bar** is the same state as the shortcut.
- **A view key** (allowed for the view alone) must not send input: a session started with the input off has a session
  that refuses each record locally. Turning the input on during such a session costs its end with
  `Input_Not_Allowed`, which the sentence of the end says.

## The screenshot

`-screenshot:<file.png>` writes the picture once the first whole screen is drawn (`screenshot.md`). With
`-screenshot-bar`, the bar is drawn as shown, so a screenshot shows both looks.

## The refused forms

- **A permanent bar of status.** It takes room from the screen for facts that a user reads once.
- **The address in the title.** The machine is known by its key.
- **A stretch to the window.** A screen of text with another proportion is unreadable.
- **Escape to leave full screen or release the input.** The machine needs its Escape.
