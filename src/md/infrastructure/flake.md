# The flake

`nix run github:sachahjkl/modus-viewer` starts the viewer on any system with Nix. With no argument, it opens on its
form; the arguments of the command line follow `--`.

## The sources that it takes

- **gui_toolkit, the submodule `ext/gui_toolkit`**, with `inputs.self.submodules = true`: the form of every program of
  the owner on gui_toolkit (cliche, atelier). The flake then sees the submodule at the commit that the repository pins,
  so one pin serves the developer, the release workflow and Nix. Nix 2.27 and later take this input; the owner's
  system has Nix 2.35 (Determinate Nix 3.24).
- **modus, the input `modus`** (`github:sachahjkl/modus`, `flake = false`), pinned by `flake.lock`: the source of the
  contract, QUIC and the cryptography (`modus_source.md`).

A second input for gui_toolkit was refused: the submodule would pin one commit and the input another, and the two
drift.

## The package

`viewertool build release` in the build of the derivation, as the release builds it, with the crates of the native
text library vendored from the toolkit's `Cargo.lock`.

- `autoPatchelfHook` sets the RUNPATH of the program to the libraries of `runtime` (Vulkan, Mesa, libglvnd, the
  libraries of X11 and Wayland, fontconfig, freetype, D-Bus);
- `wrapProgram` also sets `LD_LIBRARY_PATH` to them: what the window opens with `dlopen` is found whatever the RUNPATH
  of a library that opens it says;
- `apps.default` is the wrapped program, so `nix run` starts it.

The Vulkan driver is the system's: `/run/opengl-driver` on NixOS. With no Vulkan driver, wgpu takes OpenGL through
libglvnd.

## The checks

`nix flake check` builds the package and runs `session-tests`: the host tests of `src/session` and `src/layout`, with
no window and no toolkit, and the hooks of `pre-commit` (alejandra, deadnix, statix).
