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

## What the 93 checks still do not cover — unchanged from last round, one item worse-confirmed

The gate's "93 checks ... 20 components" phrasing invites reading coverage
as uniform across components. It is not. Re-checked this round:

- **Real file-backed sound playback is never driven, still.** Confirmed by
  reading `test/drive_window.rb:6-12` fresh this session: the comment
  explaining why only the synthetic `NoiseBin` is exercised is unchanged
  since before the last parity-reports commit. No commit this round touched
  it. This audit did not attempt its own ad-hoc reproduction run this
  session (a prior round's informal 13-sound/10-second run found no crash,
  but that was explicitly non-committed scratch work, not a regression
  test, and is not re-cited here as evidence of anything — see
  `accountability-ensurance.md`). **The state is exactly what it was last
  round: unknown, and still not gated by any committed test.** This is a
  component (`audio/bins.rb`'s `LoopBin`, backing 13 of 14 bundled sounds)
  that no check exercises, which per this task's framing is unverified, not
  done, regardless of how many of the other 93 checks pass.
- The `--hidden` CLI flag is still not exercised end-to-end via `exe/blanket`
  as a real process; the drive scripts spawn the app in-process.
- No locale other than the default is driven by any committed test — see
  `translation-parity.md`.
- The rename dialog's persistence is checked within one process
  (`drive_presets.rb` check 21), not across a real restart.
- The autostart-denial (alert dialog) and autostart-grant paths are
  read-verified, not driven — no portal daemon is available in this
  environment to produce either response. See `component-parity.md` Gap 1.

None of this makes "93 checks passed" dishonest. It means the gate's
"20 components" framing overstates what is actually exercised, in exactly
the same shape as last round, with one gap closed (the spec suite existing
at all) and the highest-severity one (real playback) completely
unaddressed since it was first flagged.

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
