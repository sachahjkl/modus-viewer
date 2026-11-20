# The settings

The settings are the toolkit's page of the preferences (`gt:prefs_page`), as in every program of the owner on
gui_toolkit. One registry of `gt:config` holds them; the user's file is `<config>/modus-viewer/prefs`.

## What is in it

- **The toolkit's standard settings**, registered whole (`prefs_page.STANDARD_ALL`): the theme, its mode and the
  machined finish, the text, the window (`window.system_title`, `window.placement`), the scrolling, the input, the
  delays, the keys, the rendering, the updates, and on the General page the messages (`general.messages`: the toasts,
  the notifications of the system, or nothing) and the language (`general.language`).
- **The viewer's own**, in the group `viewer`, on the page Viewer:

| Preference | What | Shown |
|---|---|---|
| `viewer.scale` | The default scale: `fit` or `one_to_one` | Yes |
| `viewer.input_shortcut` | The keys that switch the input: `ctrl+alt`, `ctrl+shift` or `alt+shift` | Yes |
| `viewer.bar.pinned` | The bar stays shown | Yes |
| `viewer.bar.place` | The place of the bar, as text (`interface.md`, "The bar") | No: a state of the program |
| `viewer.recent` | The last machines whose screen showed: an address and a machine key each, newest first, five at most | No: a state of the program |

## How it works

- **The file is read once, at the start, before any window**, as in the other programs: no frame waits for it.
- **The file is written off the window's thread**: `config.User_Writer` takes the registry's changes at each turn of
  the loop and writes them on its own thread. A change from the bar (its place, its pin) or from a session (a machine
  that showed its screen) is a set in the registry; the writer saves it.
- **A change applies at once**: the standard settings by `prefs_page.standard_watch`, the viewer's by
  `settings_changed`, which reads them again.
- **`modus-viewer prefs`** lists every shown preference, its value and what it does; **`modus-viewer set <name>
  <value>`** writes one; **`--pref name=value`** sets one for a run.
- **A run with no window** (`-headless`) reads the file and writes nothing: a picture leaves no trace.

## The recent machines

The form lists them above the address: "machine bae34146, at 127.0.0.1:42000". A press fills the form and connects.
A machine enters the list at the first whole frame of its session, not at Connect: a machine that never showed its
screen (a wrong address, a refused key) is not offered again. The list holds machine keys, which are public: a key of
a machine says which machine to trust, and gives no access.

## The refused forms

- **A settings window of the viewer's own.** The toolkit's page gives the search, the reset, the pages and the
  translations; a second page would drift from it.
- **The viewer key in the settings.** It is a secret: it stays in the store of secrets (`viewer_key.md`).
