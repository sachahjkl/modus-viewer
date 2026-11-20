# changelog.d

One file for each change that a user can see. A release assembles them into `CHANGELOG.md`, then deletes them. Do not
edit `CHANGELOG.md` by hand.

A fragment is `changelog.d/<yyyyMMdd-HHmmss>-<subject>.md` (subject: lowercase letters, digits and `-`):

```
type: Added

**Short summary**: what changed for the user, in one entry (no leading "- ").
```

- `type` is `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` or `Security`
  ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).
- The text is one entry of the list. It can span lines. Sub-items are indented `  - ` lines. No blank line, no heading.
- Say what changed for the user, not how the code changed.
- A change that no user can see has no fragment.

`viewertool changelog new <type> <text> [-subject:<subject>]` writes one. `viewertool check` refuses a fragment of a
wrong form. gui_toolkit's `gt:changelog` reads and assembles them.
