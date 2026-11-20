# modus viewer

See the screen of a distant machine in a window, and drive it with your keyboard and your pointer, under a key that
the owner of the machine allows.

## What it does

- It keeps one viewer key, and shows its public key. The principal of the machine allows that key in a console of the
  machine: `remote_display_allow("<key>", "view")` for the view, or `"view_and_input"` for the view and the input.
- It connects to the address and the port that you give, and accepts only the machine whose key you give.
- It draws the screen of the machine at its size, scaled to the window, and draws the pointer of the machine apart.
- With the input on, it sends your keys and your pointer.
- When the connection ends, it says why in one sentence, with the code of the end.

The machine is a machine of [modus](https://github.com/sachahjkl/modus). The viewer speaks the protocol of its service
`remote_display` over QUIC, with mutual TLS 1.3 and raw public keys. It is written in Odin, on
[gui_toolkit](https://github.com/sachahjkl/gui_toolkit), and runs on Linux and Windows.

## Use

    modus-viewer [-address:<host>:<port>] [-machine-key:<64 hexadecimal digits>] [-input] [-headless] [-screenshot:<file.png>]
    modus-viewer -print-key

With an address and a machine key, the viewer connects at its start. Else it shows a form.

- `-headless`: no window on the desktop; the window is drawn into a picture.
- `-screenshot:<file.png>`: once the first whole screen of the machine is drawn, the viewer writes the picture of its
  window to the file and ends.
- `-print-key`: prints the public key of the viewer key, for an allow on the machine, and ends.

## Build

Read [AGENTS.md](AGENTS.md), "Build and test".
