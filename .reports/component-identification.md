# blanket-rb — component identification (audit pass)

| | |
|---|---|
| Upstream | `origin/master` @ `7586dbc` |
| Port | `ruby` @ `faae9b0` |

This pass re-verifies the standing unit list and re-checks the two gaps the
previous round (`4d35191` "Parity reports", at port sha `37ac2c7`) recorded
as missing entirely: the desktop entry and the AppStream metainfo. Both have
since been added (`b815019`). This report records what changed and what is
still short.

## Unit list — all twenty upstream units have a port file

Unchanged from the previous round; re-confirmed by `find`/`git ls-tree` on
both sides:

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

## Standalone-object units — one closed, one still partial

Previous round found three units with no backing Python class missing
entirely. Re-checked this round:

| Upstream file | Port equivalent | Status |
|---|---|---|
| `data/com.rafaelmardojai.Blanket.desktop.in.in` | `data/org.rubygtkproject.Blanket.desktop.in` | **closed.** Byte-for-byte match on every field upstream has (`Name`, `Comment`, `Keywords`, `Categories`, `StartupNotify`, `X-Purism-FormFactor`), confirmed by direct diff; only `Icon=` differs (app id, correctly so) |
| `data/com.rafaelmardojai.Blanket.metainfo.xml.in.in` | `data/org.rubygtkproject.Blanket.metainfo.xml.in` | **partial.** `summary`, `description`, feature list and sound list all present and correct. **Still missing: the entire `<screenshots>` block (2 captions: "The default screen in light theme" / "...in dark theme") and the `<branding>` block** (`primary` color for light/dark scheme). Confirmed absent by `grep -c screenshot` / `grep -c branding` on the port file, both `0` |
| `data/com.rafaelmardojai.Blanket.gschema.xml.in` → `data/schemas/org.rubygtkproject.Blanket.gschema.xml` | present | unchanged from last round: the `window-state` key is retyped `(iib)` tuple → `s` (JSON string) because ruby-gnome's GSettings binding cannot round-trip a GVariant tuple through `Gio::Settings`, and its `<description>` is necessarily reworded ("A tuple containing..." → "A JSON array holding..."). Also: the port's `autostart` key now carries a `<summary>`/`<description>` upstream's schema does not have at all (upstream leaves that key undocumented) — an **addition**, not a gap, but worth naming since it is new translatable text with no upstream counterpart to match against |

## Behavioural unit that was missing — now built

`blanket/preferences.py`'s autostart flow (`Xdp.Portal#request_background` →
alert dialog on denial / toast on failure / revert either way) was absent
from `lib/blanket/preferences_dialog.rb` as of the last round. `b815019`
built it: no `Xdp` Ruby binding exists, so the port talks to
`org.freedesktop.portal.Background.RequestBackground` directly over the
session bus via `gio2`. See `component-parity.md` for the behaviour-axis
verdict on whether the replacement actually matches upstream's logic
(it does, including the asymmetric write-on-denial-while-turning-off branch).

## Scope note

This pass re-verified file coverage for all twenty units and the three
standalone units, and did a direct diff of the desktop file plus a read of
the full metainfo and gschema files. It did not re-derive a full widget/CSS/
signal table for every `lib/blanket/*.rb` file from scratch this round —
`component-parity.md` carries the axis-level verdicts for the units that
changed, and the remaining files (`sound.rb`, `main_player.rb`,
`sound_item.rb`, `volume_row.rb`, `preset_row.rb`, `preset_dialog.rb`,
`sound_context_menu.rb`, `sound_rename_dialog.rb`) are unchanged since the
last round's spot-check and were not independently rebuilt again here.
