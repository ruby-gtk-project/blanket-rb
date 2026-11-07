# blanket-rb — component identification (audit pass)

| | |
|---|---|
| Upstream | `origin/master` @ `7586dbc` |
| Port | `ruby` @ `37ac2c7` |

This pass does not re-derive the whole-app inventory from zero — the
committed `.reports/component-inventory.md` already does file-by-file tables
for every `lib/blanket/*.rb` unit and most of it is accurate work. **It is
also stale in two specific places** (see `accountability-ensurance.md`): its
prose still says "the window itself is still a placeholder" and its totals
table says "Translated strings: none", both written before `5a86733` (window
port) and `37ac2c7` (gettext wiring) respectively landed. Treat every claim in
that document as unverified until re-checked against the current tree; this
audit re-checked the two load-bearing ones in person.

## Unit list (confirmed against upstream's file tree)

Upstream module → port file, confirmed present for all twenty upstream units:

| Upstream | Port file |
|---|---|
| `blanket/main.py` | `lib/blanket/application.rb` |
| `blanket/window.py` + `data/resources/window.blp` | `lib/blanket/window.rb` |
| `blanket/sound.py` | `lib/blanket/sound.rb` |
| `blanket/main_player.py` | `lib/blanket/main_player.rb` |
| `blanket/audio/bins.py` | `lib/blanket/audio/bins.rb` |
| `blanket/mpris.py` | `lib/blanket/mpris.rb` |
| `blanket/preferences.py` + `data/resources/preferences.blp` | `lib/blanket/preferences_dialog.rb` |
| `blanket/preset.py` | `lib/blanket/preset.rb` |
| `blanket/settings.py` | `lib/blanket/settings.rb` |
| `blanket/utils.py` | `lib/blanket/dummy_item_model.rb` |
| `blanket/widgets/playpause.py` | `lib/blanket/play_pause_button.rb` |
| `blanket/widgets/preset_chooser.py` + `.blp` | `lib/blanket/preset_chooser.rb` |
| `blanket/widgets/preset_dialog.py` + `.blp` | `lib/blanket/preset_dialog.rb` |
| `blanket/widgets/preset_row.py` + `.blp` | `lib/blanket/preset_row.rb` |
| `blanket/widgets/sound_context_menu.py` + `.blp` | `lib/blanket/sound_context_menu.rb` |
| `blanket/widgets/sound_item.py` + `.blp` | `lib/blanket/sound_item.rb` |
| `blanket/widgets/sound_rename_dialog.py` + `.blp` | `lib/blanket/sound_rename_dialog.rb` |
| `blanket/widgets/volume_row.py` + `.blp` | `lib/blanket/volume_row.rb` |
| `data/resources/about.blp` | `lib/blanket/about_dialog.rb` |
| `data/resources/shortcuts.blp` | `lib/blanket/shortcuts_dialog.rb` |

All twenty upstream units have a corresponding port file. **This is file-level
coverage, not component parity** — see `component-parity.md` for the
behavioural gaps found inside several of these files.

## Units with no backing Python source — found missing entirely

Upstream ships three more translatable, user-facing units that have **no
Ruby file at all**, because they have no Python class to map from — they are
pure data files, and the component-identification skill calls these out
explicitly ("one unit per standalone object with no backing source file"):

| Upstream file | What it is | Port equivalent |
|---|---|---|
| `data/com.rafaelmardojai.Blanket.desktop.in.in` | the desktop launcher entry: `Name`, `GenericName`, `Comment`, `Keywords` | **none** — no `.desktop` file anywhere in the port tree |
| `data/com.rafaelmardojai.Blanket.metainfo.xml.in.in` | the AppStream metadata: summary, description, feature list, screenshot captions | **none** — no metainfo file anywhere in the port tree |
| `data/com.rafaelmardojai.Blanket.gschema.xml.in` → `data/schemas/org.rubygtkproject.Blanket.gschema.xml` | the GSettings schema | present, but with three key types changed (`a{ss}`/`a{sd}`/`a{sb}`/`(iib)` → `s`/JSON) and every `<description>` reworded to match — see `translation-parity.md` |

The missing desktop entry and metainfo file are **component gaps**, not
translation gaps: the app currently cannot be launched from a desktop shell's
app grid or show up in a software center under its own identity, independent
of any string inside those files. Confirmed by `find . -iname '*.desktop*'`
and `find . -iname '*metainfo*'` returning nothing under the port root.

## Behavioural unit found missing inside an existing file

`blanket/preferences.py`'s autostart switch is backed by a real flow:
`Xdp.Portal#request_background` → on success, write the setting; on refusal,
show an `Adw.AlertDialog` ("Authorization failed" / explanation / Ok); on any
other error, show an `Adw.Toast` ("The autostart request failed.") and revert
the switch. `lib/blanket/preferences_dialog.rb` maps to this file but contains
none of that: the switch just writes the GSettings key directly. No alert
dialog, no toast, no revert-on-denial. See `component-parity.md` and
`accountability-ensurance.md` for the finding and why the comment explaining
its absence is itself a problem.

## Scope note

This pass re-verified file coverage for all twenty units and did a full
props-level read of `application.rb`, `window.rb`, `preferences_dialog.rb`,
`preset_chooser.rb`, `about_dialog.rb` and `mpris.rb` against their upstream
counterparts. It did **not** re-derive a full widget/CSS/signal table for
every remaining file from scratch — the existing `.reports/component-inventory.md`
tables for `sound.rb`, `main_player.rb`, `sound_item.rb`, `volume_row.rb`,
`preset_row.rb`, `preset_dialog.rb`, `sound_context_menu.rb` and
`sound_rename_dialog.rb` were spot-checked rather than independently rebuilt
line-by-line. Anyone treating this report as proof those tables are still
accurate should re-run the scan; this audit's confidence is limited to the
items listed above.
