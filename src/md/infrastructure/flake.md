# The flake

`nix run github:sachahjkl/modus-viewer` starts the viewer on any system with Nix. With no argument, it opens on its
form; the arguments of the command line follow `--`.

## The sources that it takes

- **gui_toolkit, twice at one commit.** The developer and the release workflow build with the submodule
  `ext/gui_toolkit`; the package builds with the flake input `gui_toolkit` (`flake = false`), which it copies to
  `ext/gui_toolkit` before the build. `viewertool check` refuses a submodule and an input at two commits
  (`tools/viewertool/toolkit_pin.odin`). This is socle's form.
- **modus, the input `modus`** (`github:sachahjkl/modus`, `flake = false`), pinned by `flake.lock`: the source of the
  contract, QUIC and the cryptography (`modus_source.md`).

The submodule alone, with `inputs.self.submodules = true`, was the first form, as cliche has it. It works for a flake
fetched by git, and not for `nix run github:sachahjkl/modus-viewer`: a `github:` flake is a tarball, which carries no
submodule, and the build found no `ext/gui_toolkit`. `self.submodules` stays for a local `nix build .` from a checkout.

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
