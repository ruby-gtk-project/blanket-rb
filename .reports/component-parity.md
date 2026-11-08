# blanket-rb — component parity (audit pass)

| | |
|---|---|
| Upstream | `origin/master` @ `7586dbc` |
| Port | `ruby` @ `faae9b0` |
| Units with confirmed parity | 0 fully audited to all four axes |
| Units with a confirmed gap | 2 (one newly confirmed as a real defect, not a doc gap; one narrowed) |

This round (round 2): closed the metainfo `<screenshots>`/`<branding>` gap;
confirmed, with a committed regression test, that real file-backed sound
playback actually crashes/hangs rather than being merely suspected; and
investigated — then ruled out as currently infeasible — faking the
autostart portal in-process to drive its two remaining read-verified
branches. See `FINDINGS.md` for the full account of findings 2 and 3.
The rest of this file is carried over from the previous round's audit of
the gaps found then.

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

**Round 2 update:** investigated whether the denial and grant branches
could be driven by faking a minimal `org.freedesktop.portal.Desktop`
service in-process, on the same session bus. Found infeasible, not just
unattempted: `Gio::DBusConnection#register_object`'s automatic parameter
conversion crashes with the same `a{sv}`→Ruby `NotImplementedError`
already known from MPRIS's `Metadata` property (this time on an *inbound*
method argument), and the fallback of reading the raw message via
`#add_filter` instead crashes a different way — its callback runs on a
GDBus worker thread Ruby never registered, aborting the process
(`Ruby/GLib2-ERROR` + core dump). Both reproduced directly this round; see
`FINDINGS.md`'s second entry. The two branches remain read-verified only,
now for a documented reason rather than an assumption.

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

**Metainfo:** CLOSED this round (round 2).
`data/org.rubygtkproject.Blanket.metainfo.xml.in` now carries a
`<screenshots>` block (two `<screenshot>` entries, both captions —
"The default screen in light theme" / "...in dark theme" — present and
marked up the same way upstream marks them for translation) pointing at
the port's own screenshots under `tmp/shots/`, rather than re-using
upstream's URLs, which would misrepresent the Python app as this one. It
also carries a `<branding>` block with the same `#c0dcff` (light) /
`#0d3d76` (dark) primary accent colors upstream ships, unchanged since
they are the project's actual brand colors, not something the port should
invent its own version of.

**Verdict: parity**, for this sub-unit.

## Gap 4 (round 2) — real-sound playback: CONFIRMED BROKEN, now a tracked defect with a guarding test

Two prior rounds carried this as a suspicion, unconfirmed: the drive
suite's comment in `test/drive_window.rb` said only the synthetic
`NoiseBin` (`audiotestsrc`) is ever told to play, because a looped file
(`LoopBin`/`uridecodebin`) was suspected to crash the process via a signal
fired from a non-Ruby-registered GStreamer streaming thread.

**This round settles it with a committed, repeated-trial test —
`test/drive_real_sounds.rb`.** Result: 19 of 24 attempts (12 distinct real
bundled sounds x 2 trials) hung for the entire 16-second hard budget; only
5 survived — a 79% failure rate, intermittent rather than deterministic,
consistent with a genuine thread race rather than a guaranteed crash. A
separate unbounded run (before this test's fork+timeout harness was added)
terminated in a native SIGSEGV, caught and reported by GStreamer's own
built-in crash handler. Full account in `FINDINGS.md`'s third entry.

**Verdict: real defect, not a documentation or coverage gap.** `audio/bins.rb`'s
`LoopBin` — the code path behind 13 of the app's 14 bundled sounds — does
not work. This is now tracked as an open, confirmed, severity-1 bug
guarded by a regression test, rather than an unconfirmed suspicion routed
around silently. `test/drive_window.rb`'s avoidance of real-sound playback
stays, correctly, now backed by evidence.

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
