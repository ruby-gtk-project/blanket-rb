# Test parity — blanket-rb

| | |
|---|---|
| Upstream | `origin/master` @ `7586dbc` |
| Port | `ruby` @ `37ac2c7` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |

## Upstream has no test suite

Verified directly: `test-census.sh` against a detached `origin/master`
worktree returns zero rows, and a file-system check confirms it —
`find <upstream-tree> -iname '*test*'` returns **nothing at all**: no
`test/`, no `tests/`, no `unittest`, `pytest`, `#[test]`, `Test.add_func`, no
test target in `pyproject.toml` or `meson.build`. Blanket (upstream, Python +
PyGObject) ships no automated tests whatsoever.

**Parity is 0/0 and is met trivially.** Per the skill: this means the port
inherits **no safety net** from upstream — every check below was written for
the port and pins nothing upstream ever considered worth pinning down. That
has a real consequence for this audit: nothing in the drive suite can be
cited as "the same test upstream had", because there is no upstream test to
be the same as. Every one of the 91 checks below is this project's own
invention, and its coverage is only as good as whoever wrote the driver's own
judgment of what matters.

## The port's own suite — run fresh, not taken on faith

Ran all three drivers directly under this audit, not read from the committed
report:

```
nix develop --command xvfb-run -a ruby test/drive_window.rb    -> 26 of 26 checks passed, DRIVE OK
nix develop --command xvfb-run -a ruby test/drive_presets.rb   -> 41 of 41 checks passed, DRIVE OK
nix develop --command xvfb-run -a ruby test/drive_app.rb       -> 24 of 24 checks passed, DRIVE OK
```

91 of 91 confirmed, matching the runtime gate given for this round
(`drive_ok=true, 91 checks passed, 0 failed`). The number is real.

**But "91 checks" is not "19 components verified" in the sense that matters.**
The task's stated gate covers "19 components" — the fleet-level accounting —
while the three drive scripts between them touch the window, the sound grid,
volume popover, rename dialog, preferences dialog (4 switches), hide-inactive
filter, shortcuts dialog, about dialog, window-state round-trip, preset
add/switch/rename/remove, the application's actions/accelerators, MPRIS
properties (worked around a binding gap), the power-saver monitor's wiring
(added in the last commit) and app.quit. It does **not** drive:

- the autostart permission flow at all (because the port never built it —
  see `component-parity.md` Gap 1), so there is no check that could catch its
  absence;
- the `--hidden` command-line option end-to-end (the drive scripts spawn the
  app in-process; a genuine `--hidden` CLI invocation via `exe/blanket` was
  not exercised by this audit or, as far as the driver source shows, by the
  existing suite);
- any locale other than the default — see `translation-parity.md` for why
  "91 checks pass" says nothing about whether a single translated string
  reaches the screen;
- the rename-dialog's actual persistence across an app restart (the drive
  script's round-trip checks reload settings in the same process, not a
  fresh process).

None of this makes the 91 checks dishonest — they are real, they ran, they
passed, and the drive-verification report is candid about the one place they
had to work around a binding gap. It means **"91 checks passed" is a weaker
claim than "19 components are fully covered"**, and the gap between those two
claims is exactly where this audit found three real component gaps that no
check was ever going to catch, because none was looking there.

## The spec suite is not a suite — it has never run

`spec/` contains only `spec_helper.rb` and `README.md`. No `*_spec.rb` files
exist. Confirmed by running the dev shell's own documented spec command:

```
nix develop --command ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'
```

```
LoadError: cannot load such file -- kettle/test/rspec
0 examples, 0 failures, 2 errors occurred outside of examples
```

This was already recorded honestly in `.reports/drive-verification.md`
("there is nothing to gate on here"), re-run and reconfirmed by this audit.
**Stating this plainly, per the task's instruction: a suite that has never
been executed is a gap, and this one additionally cannot even load.** Since
upstream has no tests of its own, this is not a test-parity gap in the
bijection sense — but it is zero evidence of anything, and the project's own
`Gemfile`/`spec/` scaffolding advertises a safety net that does not exist.

## Extra

- `test/drive_window.rb` — 26 checks on the main window, sound grid, volume popover, rename dialog, preferences dialog and hide-inactive filter.
- `test/drive_presets.rb` — 41 checks on preset add/switch/rename/remove, shortcuts dialog, about dialog, window-state and custom-audio round-trips.
- `test/drive_app.rb` — 24 checks on application actions, accelerators, MPRIS (with the documented `#value`→`#to_s` workaround) and `app.quit`.

These are welcome and real, and they are listed here, outside the 0/0 count,
exactly as the skill prescribes for an app with no upstream suite.
