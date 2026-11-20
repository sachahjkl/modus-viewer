# A test machine of modus

`viewertool machine <port> <machine key> [--screenshot <file.png>]` builds the viewer, then starts it with the
address `127.0.0.1:<port>`, the machine key, and the input on. With `--screenshot`, the viewer also gets `-headless`
and `-screenshot:<file.png>` (`screenshot.md`). It is the shortest path from a machine that the tool of modus runs to a
viewer on it.

## What the tool of modus gives

`modustool run --remote-display <viewer key>`, in the modus repository (its design: "A machine for a viewer on the
host" in `src/md/features/remote_display.md` of modus):

- The machine runs with no window, as a test machine, with a new data disk. Its log goes to
  `build/run_output_remote_display.txt` of modus.
- Its network device goes to the peer of the tool. The UDP relay of the peer reaches the port 7101 of
  `remote_display`, and the datagrams come from 10.0.2.2, the one address that the listen grant of the service admits.
- The tool starts `remote_display` in the console of principal 0, then prints three lines:
  - `modustool: the UDP relay of the peer reaches the port 7101 of the machine at 127.0.0.1:<port>`;
  - `remote_display: the public key of this service: <machine key>`;
  - `modustool: connect the viewer: viewertool machine <port> <machine key>`.
- It allows the viewer key for the view and the input, waits until the last viewer ends, then stops the machine.

## The steps of a session

1. `modus-viewer -print-key` prints the public key of the kept viewer key (`viewer_key.md`).
2. In the modus repository: `modustool run --remote-display <that key>`. Wait for its three lines.
3. In this repository: `viewertool machine <port> <machine key>`, with `--screenshot <file.png>` for a picture.
4. When the viewer ends, the machine stops, and `modustool run` ends.
