# modus viewer

The native viewer of the remote display of modus: it shows the screen of a modus machine in a window, and sends the
keys and the pointer to it. It speaks the protocol of the service `remote_display` over QUIC, with mutual TLS and raw
public keys. It uses `gui_toolkit` (the submodule `ext/gui_toolkit`, collection `gt`) and the source of modus (the
flake input `modus`, collection `modus`).

Read first: [README.md](README.md), then [src/md/README.md](src/md/README.md). The design on the side of the system is
`src/md/features/remote_display.md` of the modus repository.

## Build and test

Every step is a command of `tools/viewertool`:

    odin run tools/viewertool -collection:gt=ext/gui_toolkit/src -out:build/viewertool -keep-executable -- <command>

- `nix develop` first. The shell sets `MODUS_SOURCE` to the modus source that `flake.lock` pins. The tool gives
  `-collection:modus=$MODUS_SOURCE/src/library` to each odin command. To build against another checkout of modus, set
  `MODUS_SOURCE` to its root.
- `build [release|debug]` builds `build/modus-viewer`. `build.sh` and `build.bat` are its shortcuts. With no word, the
  build has no optimisation: use it while you iterate.
- `test` runs the host tests of `src/session`: the border of each record of the machine, with no window and no socket.
- `check` runs the changelog and roadmap check, `odin check -vet`, the tests and a release build.
- `machine <port> <machine key> [--screenshot <file.png> [--bar]] [--measure]` builds the viewer and connects it to a
  test machine of modus on this computer, which `modustool run --remote-display` runs. With `--screenshot`, the viewer
  has no window and writes the picture of its window, with the bar for `--bar` (`src/md/features/screenshot.md`).
- `test` also runs the host tests of `src/layout`: the placement of the screen and the hover of the bar.
- `changelog new <type> <text>` writes a fragment.

## Rules

- What another program can use goes in gui_toolkit, generic, with its docs, tests and changelog fragment.
- Nothing slow runs on the interface thread. The connection runs on its own thread (`src/connection`). The viewer key
  is read and sealed on a worker (`src/viewer_key.odin`). The interface thread only takes their results.
- The protocol client (`src/session`) is pure: no socket, no thread, no window. Each record of the machine crosses
  the border of the contract (`modus:contract/remote_display`) before the session acts on it.
- A test tries to break the code: for each input that the code must refuse, the test gives it and checks the refusal.
  The edges come first. A test of a successful case is the last case.
- A closed set of choices is an `enum`. A word from the network becomes its enum at one place, at the border.
- Platform code goes in files with a system suffix (`*_linux.odin`, `*_windows.odin`, `*_other.odin`).
- Automation is a command of `tools/viewertool`. Do not add shell, batch, PowerShell, Python or Node scripts.
- Comments and commit messages are in English. A comment says why.
- Commits: under the identity of the owner, with no attribution trailer and no session link.

## Changelog

- `CHANGELOG.md` follows Keep a Changelog and semantic versioning. Never edit it by hand.
- A change that a user can see is one fragment in `changelog.d/` (its README gives the format), in the same commit as
  the change. `viewertool changelog new <type> <text>` writes one.
- `viewertool check` checks the fragments and the file.

## Roadmap

- `ROADMAP.md`, beside `CHANGELOG.md`, holds the planned work of the viewer: `# Roadmap`, then `## Now`, `## Next` and
  `## Later`, in this order, each a list. An optional `## Maybe` comes last.
- Each entry starts with a short bold summary, then one or two sentences on what it gives the user. No dates, no front
  matter. If a design exists, the entry links its intent file in `src/md`.
- When a work is done, remove its entry in the same commit as its changelog fragment.
- A work that touches several programs goes in the roadmap of gui_toolkit. A work on the side of modus goes in the
  roadmap of modus.
- `viewertool check` checks the format of the file with the changelog.

## Intent

This project follows <https://srcmd.org>, with the Markdown in `src/md`. Read `src/md/README.md` first.

- Change the intent first, then derive the code and the tests. A change of design changes its intent file in the same
  commit.
- Keep there what the code does not show: the purpose, the decisions, the refused forms, the subtle points.
- `src/md/README.md` lists every other file of the folder in its `## File Index`.

## Key prompts

Apply these to every task, before you write code:

- "Exercise abstract thinking when considering this task."
- "Reduce this problem to its irreducible constraints and rebuild it from zero."
- "What would a principal architect immediately rewrite before even starting this?"
- "Design the single test that breaks this design on day one."
- "What higher-level abstraction would make this entire problem disappear?"
- "Find all of the implicit state machines in my app."
