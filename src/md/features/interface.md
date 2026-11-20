# The interface

The window shows the screen of the machine, and nothing else, until the user asks for more. The first picture of the
viewer had a bar of debug facts, bands of 90 px above and under the screen, and a screen shrunk to two thirds. This
file is the interface that replaced it, in the look of the other programs of the owner on gui_toolkit.

## The look

- **The machined finish of the toolkit**, as every program of the owner: the standard settings of `gt:prefs_page`
  (`appearance.finish`, `machined` by default) and the themes of the toolkit (`theme-design.md` of gui_toolkit).
  The viewer draws nothing in its own colours: each surface is a box of the toolkit with its role.
- **The bar is a plate** (`.Plate`): the raised panel of the finish, with the radius of a control (`shape_of(.Control)`),
  its face the theme's "card background", as the find bar of the toolkit. Its buttons are the toolkit's, small; the
  indicator is a lamp of the finish (`machined_lamp`); the handle is two grooves (`machined_groove`).
- **Colours are tokens of the theme**, never names of hues: the lamp is `hue_green` under 50 ms of round trip,
  `hue_yellow` from 50 ms, `hue_red` when the connection is lost, `faint text` before the first sample. (The first bar
  asked for "green", which no theme names: the toolkit drew its colour of a missing name, magenta.)
- **Disconnect is the act of danger**: `intent = .Danger`, the theme's `danger_button`.
- **The connection screen** (connecting, ended) is a plate in the middle of the background, with its title, its
  sentence and its buttons, as a dialog of the toolkit.

## The states of the window

One enum, `View_State`, derived each frame from what the window holds. It is never stored, so it cannot disagree with
the connection.

| State | When | What the window shows |
|---|---|---|
| `Settings` | The user opened the settings | The settings page of the toolkit (`settings.md`) |
| `Form` | No session was asked yet | The form: the line that allows the viewer key, the recent machines, the address, the machine key, the input, Connect |
| `Connecting` | A connection runs, and no whole frame came | The plate in the middle: "Connecting to machine 3b0a9b25" |
| `Screen` | A whole frame came | The screen of the machine, alone |
| `Ended` | The last connection ended | The plate in the middle: the sentence of the end with its code, Retry (primary), Change the address |

## The screen fills the window

- **No bar takes room**, but the title bar of a window. The screen box is the client area under it.
- **The scale** (`src/layout`, pure, host-tested):
  - `Fit`: 1:1 when the screen fits; else the largest scale that fits, with the proportions kept.
  - A scale of 1 or more is a whole number: 1:1, 2:1, …, never 1.4:1. A scale under 1 is filtered.
  - `One_To_One`: always 1:1. A screen larger than the window moves with the pointer.
  - The default is the setting `viewer.scale` (`settings.md`); the button of the bar switches it for the session.
- **The size of the window.** At the first whole frame, a window that is not in full screen and has no kept place
  takes the size of the screen when it fits in 90 % of the monitor, else the largest size with its proportions.
- **Nearest pixels at a whole scale above 1** wait for `gt:draw`: until then, such a scale is soft (roadmap).

## Two modes

- **Windowed:** the title bar of the toolkit (`ui.title_bar`, `ui.window_buttons`), as the other programs of the owner;
  `window.system_title` gives the system's instead. The title names the machine (`machine 3b0a9b25`, the head of its
  key), never an address. The gear of the title bar opens the settings.
- **Full screen:** no title bar. The bar is the way out.

## The bar

### Its place: one union

```
Bar_Place :: union { Bar_Docked, Bar_Floating, Bar_Solo }
Bar_Docked   { edge: Top | Bottom | Left | Right, along: the share of the free run of that edge, 0 to 1 }
Bar_Floating { at: the share of the free room of the screen area on each axis, 0 to 1 }
Bar_Solo     { back: the docked or floating place to come back to }
```

- **Shares, not pixels.** A place is a share of the room that is free for the bar, so after a resize the bar is still
  inside the window, at the same proportion. A place outside the window cannot exist.
- **Docked on a side edge, the bar is vertical**: its controls in a column. A side shorter than the vertical bar is
  refused at the drop: the bar stays floating. After a resize that makes it too short, the bar is shortened to the
  side and its content is clipped; the next drop decides again.
- **Floating** is horizontal, anywhere over the screen area.
- **Solo**: the bar in a small window of its own (a second window of the toolkit on the same renderer), which the
  person places anywhere on the desktop: on a second monitor beside a machine in full screen, or to keep the screen
  free of any overlay. Closing it puts the bar back at `back`. It is always shown. A window with no system (`-headless`)
  has no solo bar.
- **The default** is docked at the top, in the middle.
- The place, the pin and the mode are kept in the settings (`viewer.bar.place`, `viewer.bar.pinned`), as text:
  `top 0.5`, `left 0.25`, `floating 0.30 0.70`, `solo bottom 0.5`. A text that reads as no place gives the default.

### Moving it

- **The handle** is at the start of the bar (its left, or its top when vertical). Pressed, the bar follows the pointer
  as a floating bar, and the edge that it would dock on is marked.
- **The drop** (`layout.bar_drop`, pure, host-tested):
  - the pointer released outside the screen area of the window: the bar goes solo, and remembers where it was;
  - else the nearest edge within the snap distance (`BAR_SNAP_EM`, 2 em: the toolkit has no snap distance of its
    own), in the order top, bottom, left, right for a tie: docked there, at the place along it where it was dropped;
  - else floating, where it was dropped.
- **The detach button** of the bar does the same as a drop outside: solo.

### When it shows

- **Pinned**: always shown, docked or floating. The pin button keeps it or lets it hide.
- **Not pinned**, a state machine (`Bar_Hover`) on the place of the host pointer, with the timing of the toolkit for a
  strip on hover (`ui.VIEW_HOVER_EDGE_EM`, `ui.VIEW_HOVER_DWELL_MS`):
  - its zone: docked, the band along its edge; floating, its own rectangle;
  - `Hidden` → `Armed` when the pointer enters the zone with no button down; `Armed` → `Shown` after the dwell;
    `Armed` → `Hidden` when the pointer leaves first;
  - `Shown` → `Leaving` when the pointer leaves the bar and the zone; `Leaving` → `Shown` when it comes back;
    `Leaving` → `Hidden` after the dwell;
  - each transition with a time asks the toolkit for a wake at its deadline (`ui.wake_within`).
- **The pointer over the bar is the window's**: its events reach the interface, never the machine.

### What it holds, each fact once

The handle; the name of the machine; the lamp and `12 ms · 60 fps` (`immediacy.md`); `1:1` or `Fit` (the button names
the other scale); `Full screen` or `Window`; the switch `Input`; the pin; the detach; `Disconnect`, red.

## The input

- **The input is held or released.** Held: the keys and the pointer over the screen go to the machine, and only the
  bar and the shortcut stay the window's. Released: the window keeps all of them.
- **The shortcut switches it**: `viewer.input_shortcut`, Ctrl+Alt by default, the shortcut of the remote desktop
  clients. Its press is not sent; the releases of its modifiers are, so no modifier stays down on the machine. A toast
  says "Input released — Ctrl+Alt to give it back", or "Input given to the machine", where `general.messages` says.
- **Escape goes to the machine**, as every other key.
- **The switch `Input` of the bar** is the same state as the shortcut.

## The screenshot

`-screenshot:<file.png>` writes the picture once the first whole screen is drawn (`screenshot.md`). With
`-screenshot-bar`, the bar is drawn as pinned at its place, so a screenshot shows both looks.

## The refused forms

- **A permanent bar of status.** It takes room from the screen for facts that a user reads once.
- **The address in the title.** The machine is known by its key.
- **A stretch to the window.** A screen of text with another proportion is unreadable.
- **Escape to leave full screen or release the input.** The machine needs its Escape.
- **A place in pixels.** A resize would leave the bar outside the window.
- **A vertical bar rotated with its text.** A turned word is read slower than a column of buttons.
