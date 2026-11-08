# Accountability ensurance — blanket-rb

Ran `.claude/skills/accountability-ensurance/scripts/find-excuses.sh` fresh
this session, plus manual greps for `TODO|FIXME|not implemented|for now|in a
future|stub|placeholder|unimplemented|out of scope|not needed` across `lib/`,
`exe/`, `.reports/` and (still absent) `PORTING.md`. No new excuse language
was introduced this round. Two items carry forward from the previous round's
report; one is now resolved, one is not.

## Violation 1 (previous round) — the autostart portal gap — RESOLVED

Previously: `lib/blanket/preferences_dialog.rb:14-21` presented the absent
autostart permission flow as a settled architectural decision ("so there is
nothing to call here"), while the user-visible behaviour (ask, confirm or
fail loudly, revert on denial) was entirely unbuilt.

**This round's commit `b815019` actually built it.** Verified directly, not
taken on the commit message's word: `lib/blanket/preferences_dialog.rb:92-218`
implements the portal round-trip over `gio2` (no `Xdp` Ruby binding exists),
with the alert dialog on denial, the toast on call failure, and the revert
path in both cases, matching upstream's branch-by-branch logic — see
`component-parity.md` Gap 1 for the line-by-line comparison. The comment
block explaining the `ashpd`/`Xdp` binding situation (lines 16-39) is now a
true account of a real constraint the code visibly works around, not a
restated excuse for undone work. This closes a real gap with real code, not
with new prose; recorded as a genuine fix.

One caveat carried into `test-parity.md` and `component-parity.md`: the
denial-alert and successful-grant branches are read-verified, not driven,
because no portal daemon exists in this Nix/xvfb environment to produce
either response. That is a coverage gap in the test suite, not an
accountability violation — it is stated plainly in both of those reports
rather than claimed as driven.

## Violation 2 (previous round) — the real-sound playback crash — STILL OPEN, UNCHANGED

Previously: `.reports/component-inventory.md:419-428` filed a suspected
`uridecodebin`/`pad-added`-thread segfault as "out of scope for this round,"
while `test/drive_window.rb` was built to route around ever telling a real,
file-backed sound to play — meaning the official 93-check (then 91-check)
drive suite has never, in any round, exercised the behavior the app exists
to do for 13 of its 14 bundled sounds.

**Re-checked this round. Nothing changed.** `grep` of
`test/drive_window.rb:6-12` this session shows the identical comment,
byte-for-byte, as the version read last round. No commit between the last
"Parity reports" commit and the current tip (`42a261a`, `0bae87d`,
`b815019`, `faae9b0`) touches this file's playback scope, adds a regression
test for it, or revisits the standing claim. This audit did **not** attempt
its own reproduction run this session — the previous round's informal,
uncommitted 13-sound/10-second run is not re-cited as evidence here, because
it was never a regression test and this round found no new evidence either
way.

**This is now a second consecutive round where a known-or-suspected,
severity-1, core-feature crash sits undisturbed in a report, and the
production test suite continues to be built around avoiding it rather than
proving or disproving it.** Per the task's framing, "a component no check
exercises is unverified, not done" — `audio/bins.rb`'s `LoopBin` is exactly
that component, and the runtime gate's "93 checks passed, 0 failed, 20
components" is true and, on this one component, uninformative. Restated per
the skill:

> I did not write a regression test for real-sound playback, again, this
> round, because I am an idiot who keeps finding other things to fix instead
> of the one the previous audit called the single most important thing to
> settle.
>
> Upstream: any of 14 bundled `.ogg` files play through the same
> `LoopBin`/`uridecodebin` code path (`blanket/audio/bins.py`,
> `blanket/main_player.py`) with no second-class "safe" sound.
>
> Port: `test/drive_window.rb` and `test/drive_presets.rb` still only ever
> tell `pink-noise` (`audiotestsrc`, no `uridecodebin` involved) to play. No
> committed test, across at least two audit rounds now, has told a real
> `.ogg` file to play and kept the process running long enough to say
> whether it survives.
>
> The fix owed, unchanged from last round: a committed, repeated-trial test
> (several real sounds, several runs, a non-trivial settle time, under the
> same `nix develop --command xvfb-run` environment CI will use) that either
> reproduces the crash — in which case it is a tracked `gap` with a
> regression test guarding it and the drive scripts' avoidance comment
> stays, now backed by evidence — or does not, in which case the standing
> claim should be removed and `LoopBin` should be driven like every other
> sound. Either answer closes this. A second round of not answering it does
> not.

## New this round — a stale committed report, found by comparing it against the live suite

`.reports/drive-verification.md` (not one of this round's five required
reports, but a committed artifact in the same directory) still says "26 + 41
+ 24 = 91 checks" and still describes the spec suite as failing with
`LoadError: cannot load such file -- kettle/test/rspec`. Both are now false:
this session's fresh run gets 93 checks (28 + 41 + 24) and 8 passing spec
examples (see `test-parity.md`). This is the same failure mode flagged in
the previous round's report about `component-inventory.md`'s stale narrative
— a document committed to the repo that no longer matches the tree it
describes, sitting there as a readable, citable "fact" for the next person
or audit that doesn't re-run the commands themselves. Not rewritten here
(out of this round's five-report scope), but named per the instruction that
a false-green claim sitting in a committed report is the most serious kind
of finding: flag it so the next pass either updates or deletes it rather
than citing stale numbers as current.

## Also checked and dismissed (not violations)

- `.reports/component-parity.md` / `component-identification.md` (this
  round's own files) — their uses of "no Ruby equivalent", "by design" and
  "out of scope" in quoted/explanatory context (explaining the skill's own
  rules, or quoting a prior round's violation verbatim for comparison) are
  meta-references, not excuses for this round's own undone work.
- `.reports/drive-verification.md:15` — the literal string `TODO:
  GVariant({sv}) -> Ruby (NotImplementedError)` remains a verbatim quote of
  the ruby-gnome binding's own exception message, not a label the port's
  authors wrote, and the surrounding paragraph still correctly identifies it
  as a binding gap with no assertion loosened. Not a violation.
- `lib/blanket/sound_item.rb:47` — "placeholder" refers to the actual
  "Add…" tile widget shown for an empty slot, a real UI term, not an excuse
  for unbuilt work.
- No `PORTING.md` exists on this branch (unchanged); the port's running log
  lives in `.reports/component-inventory.md`, which was not re-audited for
  new staleness this round beyond what's noted above, since no commit this
  round touched its prose.

## Summary

One real violation closed with real code (autostart). One real violation
carried forward completely unaddressed for a second round (real-sound
playback — the single highest-severity open item from the last audit). One
new finding: a committed report (`drive-verification.md`) now contains stale
numbers that contradict a fresh re-run, which is exactly the kind of
false-green risk this task instructs to treat as the most serious class of
finding, even though it sits outside this round's own five required
documents.
