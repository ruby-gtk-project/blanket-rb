# blanket-rb — component parity (audit pass)

| | |
|---|---|
| Upstream | `origin/master` @ `7586dbc` |
| Port | `ruby` @ `faae9b0` |
| Units with confirmed parity | 0 fully audited to all four axes |
| Units with a confirmed gap | 2 (down from 3 last round; 1 closed) |

This is a targeted re-audit of the three gaps the previous round found,
plus one new finding this round surfaced while re-verifying them. It is
not a from-scratch four-axis pass over every unit — see the Scope note.

## Gap 1 — the autostart permission flow — CLOSED

**Upstream:** `blanket/preferences.py:66-95`. `Xdp.Portal#request_background`;
on denial while turning the switch on, an `Adw.AlertDialog` ("Authorization
failed" / explanation / "Ok") and revert; on any other exception, an
`Adw.Toast` ("The autostart request failed.") and revert; on success (or on
denial while turning the switch *off*), the setting is written.

**Port, as of `b815019`:** `lib/blanket/preferences_dialog.rb:92-218`. No
`Xdp` Ruby binding exists, so the port calls
`org.freedesktop.portal.Background.RequestBackground` directly on the
session bus via `gio2`, subscribing to the `Request` object's `Response`
signal before sending the call (avoiding the race a naive port would hit).
Read line-by-line against upstream's `finish` callback:

| Branch | Upstream | Port | Match |
|---|---|---|---|
| Granted | write setting | `response_code.zero?` → write setting | ✓ |
| Denied, switch going on | alert + revert | `elsif active` → `show_autostart_denied` (alert + revert) | ✓ |
| Denied, switch going off | write setting anyway | `else` → write setting anyway | ✓ |
| Call fails outright (no portal daemon) | toast + revert | `rescue StandardError` in the `bus.call` block → `on_autostart_request_failed` (toast + revert) | ✓ |

Driven directly by this audit (`test/drive_window.rb` checks 16-17, re-run
fresh this session): with no portal daemon running in the Nix/xvfb
environment, toggling the switch on triggers the call-fails branch, the
switch reverts, and the setting is confirmed unwritten. This exercises the
toast/revert path but **not** the alert-dialog/denial path or the success
path — no portal daemon is available in this environment to grant or deny,
so those two branches are verified by reading, not by driving.

**Verdict: parity on the paths this environment can drive; the
denial-alert and grant paths are read-verified only, not driven.** Noting
this distinction rather than calling the whole flow "driven," per the task's
instruction that an unexercised path is unverified, not done.

## Gap 2 — the preset chooser's tooltip — CLOSED

**Upstream:** `data/resources/window.blp:22` — `tooltip-text: _("Presets
Menu")`.

**Port:** `lib/blanket/preset_chooser.rb:77` — `button.tooltip_text =
_("Presets Menu")`. Confirmed present, confirmed byte-identical msgid in the
translation census (`/tmp/port_keys.tsv` this session).

**Verdict: parity.**

## Gap 3 — desktop entry and metainfo — PARTIALLY CLOSED

**Desktop entry:** closed. `data/org.rubygtkproject.Blanket.desktop.in`
diffs byte-identical against upstream on every field but `Icon=` (correctly
the port's own app id). Confirmed by direct `git show origin/master:...`
vs. the port file, this session.

**Metainfo:** still a gap. `data/org.rubygtkproject.Blanket.metainfo.xml.in`
carries the summary, description, feature list and sound list, but has
**no `<screenshots>` block and no `<branding>` block** — confirmed absent by
grep this session. Two msgids (`The default screen in light theme`, `...in
dark theme`) have no home in the port at all; a software center showing this
app's listing would show no screenshots and the generic theme color instead
of the app's own `#c0dcff` / `#0d3d76` accent.

**Verdict: gap**, narrower than last round (the file now exists and most of
its content is correct) but not closed.

## New this round — real-sound playback has no component-parity coverage

Re-checking `.reports/accountability-ensurance.md`'s standing note (both
this round's and the carried-over prior one): the drive suite's own comment
in `test/drive_window.rb:6-12` states, unchanged since before the last
"Parity reports" commit, that only the synthetic `NoiseBin`
(`audiotestsrc`) is ever told to play, because a looped file
(`LoopBin`/`uridecodebin`) is suspected to crash the process via a signal
fired from a non-Ruby-registered GStreamer thread. **No test, this round or
any prior round, has driven a real file-backed sound and confirmed the
process survives.** `audio/bins.rb`'s `LoopBin` is therefore a component
with zero behaviour-axis coverage of its primary code path — the one GTK
signal integration this app depends on to play 14 of its 14 bundled sounds.
See `accountability-ensurance.md` for why this is carried forward rather
than treated as newly resolved.

## What this audit did check and found clean (unchanged from last round)

- `lib/blanket/about_dialog.rb` against `about.blp` + `main.py`'s
  `on_about`.
- `lib/blanket/application.rb`'s actions/accelerators.
- `lib/blanket/mpris.rb`'s documented `Metadata` binding gap, correctly
  recorded as a binding defect.

## Scope note — what was not audited

As last round: no full four-axis comparison (widget count, CSS, signals,
text) was run over every one of the twenty mapped units this pass either.
`sound_item.rb`, `sound.rb`, `main_player.rb`, `audio/bins.rb` (aside from
the playback-coverage finding above), `volume_row.rb`, `preset_row.rb`,
`preset_dialog.rb`, `sound_context_menu.rb` and `sound_rename_dialog.rb`
were not re-driven signal-by-signal this round. No unit in this report is
marked "parity" at the whole-unit level for this reason — the gate the
skill sets for that word was not fully cleared for any unit.
