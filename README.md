# modus viewer

See the screen of a distant machine in a window, and drive it with your keyboard and your pointer, under a key that
the owner of the machine allows.

## Run it

    nix run github:sachahjkl/modus-viewer

It opens on its form. Arguments follow `--`: `nix run github:sachahjkl/modus-viewer -- -print-key`.

## What it does

- It keeps one viewer key, and shows its public key. The principal of the machine allows that key in a console of the
  machine: `remote_display_allow("<key>", "view")` for the view, or `"view_and_input"` for the view and the input.
- It connects to the address and the port that you give, and accepts only the machine whose key you give. The last
  machines whose screen showed come back in the form.
- The screen of the machine fills the window: 1:1 when it fits, else as large as it fits, with its proportions. In a
  window or in full screen.
- A bar holds the name of the machine, the round trip and the frames of the last second, 1:1 or Fit, Full screen,
  Input, its pin, Settings and Disconnect. Its handle moves it: docked to an edge, floating over the screen, or in a
  small window of its own. Unpinned, it shows when the pointer rests where it is.
- With the input held, your keys and your pointer go to the machine, Escape too. Your own cursor is the cursor: it
  never waits for the machine. Ctrl+Alt releases the input, and gives it back.
- While it connects, and when the connection ends, it says so in the middle of the window, with the reason and its
  code, and Retry.
- Settings, English and French, updates, a report of a crash: as the other programs on gui_toolkit.

The machine is a machine of [modus](https://github.com/sachahjkl/modus). The viewer speaks the protocol of its service
`remote_display` over QUIC, with mutual TLS 1.3 and raw public keys. It is written in Odin, on
[gui_toolkit](https://github.com/sachahjkl/gui_toolkit), and runs on Linux.

## Use

    modus-viewer [-address:<host>:<port>] [-machine-key:<64 hexadecimal digits>] [-input]
                 [-headless] [-screenshot:<file.png>] [-screenshot-bar] [-measure]
    modus-viewer -print-key
    modus-viewer prefs | set <name> <value>     [--pref name=value]

With an address and a machine key, the viewer connects at its start. Else it shows a form.

- `-input`: the input is held from the start.
- `-headless`: no window on the desktop; the window is drawn into a picture.
- `-screenshot:<file.png>`: once the first whole screen of the machine is drawn, the viewer writes the picture of its
  window to the file and ends. `-screenshot-bar` shows the bar in it.
- `-measure`: at the end, prints the round trip, the interval between the frames, and the dropped frames.
- `-print-key`: prints the public key of the viewer key, for an allow on the machine, and ends.
- `prefs`, `set`: the preferences, with no window.

## Build

Read [AGENTS.md](AGENTS.md), "Build and test".
