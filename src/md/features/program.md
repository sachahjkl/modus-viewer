# The program

The viewer has the set of the other programs of the owner on gui_toolkit (atelier is the smallest one, and the model),
and no more: the settings (`settings.md`), the languages, the crash report, the updates, about, and the place of the
window kept between runs.

## The start

1. The arguments of the command line, then the registry with the user's file (`settings.md`).
2. `host.program_start`: the log of the program and the reports of a crash, before any thread and any window. The
   report of a crash of the last run shows in the toolkit's crash bar at the top of the window (`gt:crash_bar`), with a
   way to file it on the repository.
3. `prefs_page.language_start`: the language of `general.language` (the system's by default) from the toolkit's
   catalogues and the viewer's (`i18n/fr.txt`). Every text that the viewer shows goes through `i18n.tr` or
   `i18n.later`: English is the key, French is the first other language. `viewertool i18n fr` writes the catalogue from
   the code; `viewertool check` refuses a text with no translation.
4. The window, with the toolkit's title bar unless `window.system_title`, at the place that `window.placement` kept
   (`prefs_page.placement_restore`; Wayland places it itself). The place is followed during the run and kept at the end.
5. The theme of `appearance.theme`, in the finish of `appearance.finish` (machined by default), applied by the params
   of each build (`ui.theme_show`), as in atelier.

A run with no window (`-headless`) does steps 1, 3 and 5 only: it reads the preferences, writes no file, opens no log
and checks no update.

## The updates

`gt:update` through `prefs_page.updates_start`: the latest release of `sachahjkl/modus-viewer` a while after the start
and then every day; a new version is downloaded, checked against its manifest signed by the update key of the viewer
(`src/update/product.odin`), and put in place; the new viewer runs at the next start, or at once by Restart now. The
title bar shows the toolkit's badge of an update; a toast says what the badge cannot (`update.notice`).

- **The update key.** `viewertool update keygen` made the pair. The public half is in `src/update/product.odin`. The
  private half is in `secrets/production.yaml`, encrypted with sops for the maintainer's age key, and in the secret
  `UPDATE_SIGNING_KEY` of the GitHub repository, which the release workflow reads.
- **The release.** `viewertool ship <patch|minor|major>` writes the changelog, the version, commits, tags and pushes;
  the tag starts `.github/workflows/release.yml`, which builds on Debian 12 with the modus source that `flake.lock`
  pins, runs `viewertool check`, packages the archive and the signed update, and publishes the release.
- **A copy from the Nix store** is left to Nix: `update.auto` does nothing there.
- **Linux only** for now: the Windows build of the modus packages is not checked by a run yet.

## About

The title bar's button (and the form's, under a system title bar) says, where `general.messages` says: "modus viewer
0.1.0, on gui_toolkit 0.331.1. https://github.com/sachahjkl/modus-viewer". It is classeur's form: a sentence, not a
window: the program has nothing else to say about itself.

## The refused forms

- **An installer of the viewer's own** (`gt:setup`'s install, a menu entry, an uninstaller). atelier has one because it
  installs programs; the viewer is installed by Nix or by its archive. It is not in the set that the owner asked for.
- **One copy at a time** (`gt:instance`). Two viewers on two machines at once is a use, not a fault.
