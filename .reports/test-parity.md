# Test parity — blanket-rb

| | |
|---|---|
| Upstream | `origin/master` @ `7586dbc` |
| Port | `ruby` @ `faae9b0` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps (bijection sense) | 0 |

## Upstream has no test suite

Re-confirmed this round: `find <upstream-tree> -iname '*test*'` against a
fresh `origin/master` worktree returns nothing. No `test/`, no `pytest`, no
test target in `pyproject.toml` or `meson.build`. Parity in the bijection
sense (every upstream test ported) is met trivially at 0/0, which means
every check below is the port's own invention and pins only what this
project decided mattered.

## The port's drive suite — re-run fresh this session, not read from a prior report

```
nix develop --command xvfb-run -a ruby test/drive_window.rb    -> 28 of 28 checks passed, DRIVE OK
nix develop --command xvfb-run -a ruby test/drive_presets.rb   -> 41 of 41 checks passed, DRIVE OK
nix develop --command xvfb-run -a ruby test/drive_app.rb       -> 24 of 24 checks passed, DRIVE OK
```

28 + 41 + 24 = **93 of 93**, matching the runtime gate given for this round
exactly. The number is real and reproduced independently, not taken on
faith. `drive_window.rb` grew from 26 checks (last round) to 28 — the two
new checks are the autostart-portal round-trip (checks 16-17: request
fails with no portal daemon present, switch reverts, setting unwritten).

## The spec suite now runs — a real fix, not yet a safety net

Last round: `spec/` loaded `kettle/test/rspec`, which the dev shell does not
install, and the suite errored before a single example ran — "a suite that
has never been executed." This round (`faae9b0`) fixed the load path and
added `spec/blanket/define_spec.rb`. Re-run fresh this session:

```
nix develop --command ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format","progress","--require","spec_helper","spec"])'
-> 8 examples, 0 failures
```

Real, confirmed, and a genuine first. **Scope it correctly, though**: the
new spec file covers only `Blanket::Define` — the sound catalogue and
credits tables, a small data module with no GTK dependency. It does not
touch any widget, dialog, signal or action; that coverage is still 100% the
drive scripts' job. "The spec suite runs" is not "the spec suite covers the
app" — it covers the one module that was the easiest thing to test in
isolation.

## Real file-backed sound playback — CONFIRMED this round, no longer just suspected

This was the single highest-severity open item from the last two rounds:
`test/drive_window.rb` only ever tells the synthetic `NoiseBin`
(`pink-noise`, `audiotestsrc`) to play, routing around a suspected
thread-safety crash in `uridecodebin`'s `"pad-added"` signal, and no
committed test had ever told a real `.ogg` file to play.

**Settled this round, and the answer is: it crashes/hangs, most of the
time.** `test/drive_real_sounds.rb`, new this round, forks each sound's
play attempt with a hard wall-clock budget (so a hang cannot hang the test
itself) and tried 12 distinct real bundled sounds across 2 trials:

```
nix develop --command xvfb-run -a ruby test/drive_real_sounds.rb
```

Result: **19 of 24 attempts (12 sounds x 2 trials) hung for the entire
16-second hard budget; only 5 survived.** A 79% failure rate, not 100% —
intermittent, not deterministic, which matches "suspected thread-safety
crash" exactly: a race, not a guaranteed failure. A separate, earlier
unbounded run (no fork, no hard timeout) did not merely hang: it ended
with GStreamer's own built-in signal handler dumping a native backtrace
and `/proc/self/maps` to stderr, i.e. a real SIGSEGV. Full account in
`FINDINGS.md`'s third entry.

This is a real, reproduced, severity-1 defect, not a benign quirk: the
port's core feature (play an ambient sound) does not work today for 13 of
its 14 bundled sounds. It is an open gap, tracked here and in
`component-parity.md`, guarded by a committed regression test rather than
an unconfirmed suspicion. `test/drive_window.rb`'s avoidance of real-sound
playback was the right call, and its comment now says so with evidence
instead of suspicion.

## What the 93 checks still do not cover — re-checked this round

The gate's "93 checks ... 20 components" phrasing invites reading coverage
as uniform across components. It is not. Re-checked this round:

- **Real file-backed sound playback was never driven — now it is, and it
  fails.** See above; no longer an unknown.
- The `--hidden` CLI flag is still not exercised end-to-end via `exe/blanket`
  as a real process; the drive scripts spawn the app in-process.
- No locale other than the default is driven by any committed test — see
  `translation-parity.md`.
- The rename dialog's persistence is checked within one process
  (`drive_presets.rb` check 21), not across a real restart.
- The autostart-denial (alert dialog) and autostart-grant paths are still
  read-verified, not driven. This round investigated faking a portal
  daemon in-process over `gio2`/`gobject-introspection` and found it is
  not currently feasible: two independent, reproduced crashes (an
  `a{sv}`-conversion `NotImplementedError` on the inbound
  `RequestBackground` call, and a `Ruby/GLib2-ERROR` core dump from
  `add_filter`'s callback running on an unregistered GDBus worker thread).
  See `FINDINGS.md`'s second entry and `component-parity.md` Gap 1.

None of this makes "93 checks passed" dishonest. It means the gate's
"20 components" framing overstates what is actually exercised. This round
closes the single worst gap (real playback: now known, not unknown) and
narrows the autostart-portal gap from "nothing tried" to "tried, and found
infeasible with the current bindings, for documented reasons."

## Extra

- `test/drive_window.rb` — 28 checks: main window, sound grid, volume
  popover, rename dialog, preferences dialog (dark mode, inhibition,
  **autostart portal round-trip**), hide-inactive filter.
- `test/drive_presets.rb` — 41 checks: preset add/switch/rename/remove,
  shortcuts dialog, about dialog, window-state and custom-audio round-trips.
- `test/drive_app.rb` — 24 checks: application actions, accelerators, MPRIS
  (documented `#value`→`#to_s` workaround), `app.quit`.
- `spec/blanket/define_spec.rb` — 8 examples: sound catalogue and credits
  tables, no GTK dependency.

These are welcome and real, and are listed outside the 0/0 bijection count,
exactly as the skill prescribes for an app with no upstream suite.
