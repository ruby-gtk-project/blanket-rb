# blanket-rb — component parity (audit pass)

| | |
|---|---|
| Upstream | `origin/master` @ `7586dbc` |
| Port | `ruby` @ `37ac2c7` |
| Units with confirmed parity | 0 fully audited to all four axes |
| Units with a confirmed gap | 3 |

This is an adversarial spot-audit, not a from-scratch four-axis pass over
every unit in `component-identification.md`. It targeted the units most
likely to carry behavioural gaps (dialogs, the preferences flow, the data
files with no Ruby equivalent) and confirmed three real gaps. It does not
clear any unit as "parity" — see Scope note at the bottom.

## Gap 1 — the autostart permission flow (behaviour axis)

**Upstream:** `blanket/preferences.py:66-95`. The autostart switch calls
`Xdp.Portal#request_background` through the XDG Background portal. On the
async callback:
- portal refused and the switch is still on → `Adw.AlertDialog.new(_("Authorization failed"), _("Make sure Blanket has permission to run in the background in Settings → Applications → Blanket and try again."))`, with an `_("Ok")` response, presented over the window, and the switch is reverted to its last saved value.
- any other exception → `Adw.Toast(title=_("The autostart request failed."))` added to the toast overlay, and the switch is reverted.
- success → the setting is written.

**Port:** `lib/blanket/preferences_dialog.rb:79` (`autostart_row`) and its
binding to `Settings#autostart=`. There is no portal call, no alert dialog, no
toast, and no revert path — flipping the switch always just writes the
setting. A user who has the background permission denied by their desktop
(or who has no portal implementation at all) gets a switch that silently
claims success with no way to find out it did not take effect.

**Verdict: gap.** Three translatable strings (`Authorization failed`, the
long explanation, `Ok`) and one toast string (`The autostart request
failed.`) have no home anywhere in the port — confirmed against the
translation census in `translation-parity.md`.

The comment at `lib/blanket/preferences_dialog.rb:14-21` explaining this
absence is itself flagged in `accountability-ensurance.md` — it reads as a
closed architectural decision, which it is not.

## Gap 2 — the preset chooser's tooltip (text + accessibility axis)

**Upstream:** `data/resources/window.blp:22` — `$PresetChooser
presets_chooser { tooltip-text: _("Presets Menu"); }`.

**Port:** `lib/blanket/preset_chooser.rb` — `grep -n tooltip` returns nothing.
No tooltip text is set anywhere the chooser is built (`lib/blanket/window.rb`'s
`header_bar.title_widget = presets_chooser.build` call site also sets none).

**Verdict: gap.** One widget, missing one attribute upstream gives it, on
both the behaviour axis (no tooltip shown on hover) and the text axis (the
msgid `Presets Menu` is unreachable — confirmed as a gap in
`translation-parity.md`).

## Gap 3 — no desktop entry, no AppStream metadata (whole units)

See `component-identification.md`. `data/com.rafaelmardojai.Blanket.desktop.in.in`
and `data/com.rafaelmardojai.Blanket.metainfo.xml.in.in` have no port
equivalent at all. Every string those two files carry — `Keywords`, the
AppStream summary/description/feature list/screenshot captions — is a text-axis
gap with nowhere in the port to even attach a `_()` call. These are listed
here rather than only in translation-parity because the files themselves,
not just their strings, are the missing component.

## What this audit did check and found clean

- `lib/blanket/about_dialog.rb` against `data/resources/about.blp` +
  `main.py`'s `on_about`: `Source Code` link, both credit sections, and
  `translator-credits` (verified `_("translator-credits")` is present and
  wired to `dlg.translator_credits=`) all correspond correctly. (The
  translation census's apparent "gap" on this string is a scanner artifact —
  a `.blp` translator comment line bleeding into the msgctxt column on the
  upstream side only — not a real mismatch; see `translation-parity.md`.)
- `lib/blanket/application.rb`'s 14 `app.*`/`win.*` actions and 6
  accelerators: spot-checked against `main.py` and confirmed present,
  including `--hidden` and the power-saver monitor the last commit added.
- `lib/blanket/mpris.rb`'s documented `Metadata` property binding gap
  (`GVariant({sv}) -> Ruby` `NotImplementedError`) is a real ruby-gnome
  limitation, correctly recorded in `.reports/drive-verification.md` as a
  binding defect rather than smoothed over — the drive script's check reads
  `#to_s` instead of `#value` and says why in a comment. This is the right
  way to record a binding gap; contrast with Gap 1 above.

## Scope note — what was not audited

This pass did not run a full four-axis comparison (widget count, CSS,
signals, text) over every one of the twenty mapped units. `sound_item.rb`,
`sound.rb`, `main_player.rb`, `audio/bins.rb`, `volume_row.rb`,
`preset_row.rb`, `preset_dialog.rb`, `sound_context_menu.rb`,
`sound_rename_dialog.rb` and `shortcuts_dialog.rb` were read for structure but
not driven signal-by-signal against upstream's `.blp`/`.py` pairs. No unit in
this report is marked "parity" — the gate the skill sets for that word
(every row `parity`, stylesheet clean, messages clean, driven line with no
✗) was not fully cleared for any unit, so none is claimed.
