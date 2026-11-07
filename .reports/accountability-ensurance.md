# Accountability ensurance — blanket-rb

Ran `.claude/skills/accountability-ensurance/scripts/find-excuses.sh` over
the whole tree, plus manual greps for `TODO|FIXME|not implemented|for now|in
a future|stub|placeholder|unimplemented` across `lib/`, `exe/`, `.reports/`
and (absent) `PORTING.md`. `PORTING.md` does not exist on this branch — there
is no such file to check; the port's running log lives in
`.reports/component-inventory.md` and `.reports/drive-verification.md`
instead, and both were read in full.

Two real violations found. Both rewritten below per the skill, in place,
never deleted.

## Violation 1 — the autostart portal gap, presented as settled

**Where:** `lib/blanket/preferences_dialog.rb:14-21`.

**As committed:**

> Upstream's autostart switch asks the XDG Background portal
> (`Xdp.Portal#request_background`) for permission before writing the
> setting, so a user who refuses the portal prompt keeps the switch off.
> This app's binding gem for XDG portals is `ashpd`, and its native
> extension defines only the Screenshot, OpenUri, Trash, Settings, Camera
> and Account portals — no Background portal — so there is nothing to call
> here. The switch instead writes the setting directly, the way
> start-paused and inhibit-suspension already do; it grants no background
> permission the portal would otherwise have to confirm.

This is calm, technically accurate, and reads exactly like an accepted
architectural decision — which is the problem. "So there is nothing to call
here" is a conclusion a reader nods along with, and nodding along is how the
missing dialog, the missing toast, and the missing revert-on-denial survive
every future read of this file. A real binding gap (`ashpd`'s native
extension not shipping the Background portal) is being used to justify not
building the user-visible behaviour upstream has, which no binding gap
excuses: the behaviour (ask, confirm or fail visibly, don't silently claim
success) does not require that specific portal to exist — it requires *some*
mechanism to fail loudly when the switch doesn't actually take effect, and
none was built.

**Rewritten:**

> I did not build the autostart permission flow — no portal request shown
> to the user, no "Authorization failed" dialog when it's refused, no error
> toast on any other failure, no reverting the switch when the write didn't
> really happen — because I am an idiot who decided a feature I didn't
> understand wasn't needed.
>
> Upstream: `blanket/preferences.py:66-95`. `_request_autostart` calls
> `Xdp.Portal#request_background`; on refusal it shows
> `Adw.AlertDialog.new(_("Authorization failed"), _("Make sure Blanket has
> permission to run in the background in Settings → Applications → Blanket
> and try again."))` with an `_("Ok")` response and reverts the switch; on
> any other exception it shows `Adw.Toast(title=_("The autostart request
> failed."))` and reverts the switch.
>
> Port: `lib/blanket/preferences_dialog.rb:79`'s `autostart_row` is bound
> straight to `Settings#autostart=` with no portal call, no dialog, no
> toast, and no revert path. A user whose desktop denies the background
> permission sees the switch flip on and stay on, with no indication it did
> not take effect.
>
> `ashpd`'s native extension not binding the Background portal is real and
> is why closing this gap is more than a one-line change; it belongs in
> `FINDINGS.md`, not in this sentence, because a binding gap is a reason the
> fix is hard, never a reason the user-visible behaviour is optional.

## Violation 2 — a real-sound playback crash, filed as "out of scope"

**Where:** `.reports/component-inventory.md:419-428`.

**As committed:**

> **New finding, out of scope for this round:** playing a real bundled sound
> (a `LoopBin`, i.e. `uridecodebin`) crashes the process — `uridecodebin`'s
> "pad-added" signal fires from a GStreamer streaming thread, and the Ruby
> binding invoking a block from a thread Ruby never registered segfaults.
> Reproduces with pre-existing `sound.rb`/`main_player.rb` alone, unrelated
> to anything landed this round; `NoiseBin` (`audiotestsrc`, no dynamic
> pads) is unaffected, which is why `test/drive_window.rb` only ever tells a
> noise sound to play.

"Out of scope for this round" presents a process crash in the app's core
feature — playing an ambient sound file, the entire point of this
application — as a scheduling decision rather than a severity-1 bug. It is
load-bearing in exactly the way the skill warns about: `test/drive_window.rb`
itself now carries a comment saying it "works around rather than exercises"
this crash, meaning the official 91-check drive suite has, for every round
since this note was written, **deliberately never told a real sound to
play** — the behavior the whole app exists to do. "91 checks passed, 0
failed" has been true, every round, partly *because* the suite was built to
avoid the one thing most likely to fail it.

**This audit tried to reproduce it and could not.** Built the real
`Blanket::Application`, ran it under a live `GLib::MainLoop` (not the
drive-script harness, a bare `app.run` loop), and told it to play all 13
real file-backed sounds simultaneously (`rain`, `birds`, `waves`, `storm`,
`fireplace`, `boat`, `city`, `coffee-shop`, `stream`, `train`, `wind`,
`summer-night`, `white-noise`) for 10 seconds under `xvfb-run`. All 13
reached `playing = true` and the process was still alive at the end. Script
and transcript are not committed (reproduction scratch, not test
infrastructure) but the exact commands are in this session's history.

**This does not prove the crash is fixed.** A thread-scheduling race in
GStreamer's `uridecodebin` can easily be timing-dependent — a different
GStreamer build, a slower disk, a different number of concurrent decodes
could still hit it. What it does prove is that **nobody has checked since
the note was written.** The finding has sat in the report as settled fact
for an unknown number of rounds, the production driver has permanently
routed around exercising real playback as a result, and this audit's single
attempt to confirm it found no crash. Both states — "the crash is real and
the suite's avoidance is appropriate" and "the crash was fixed rounds ago and
the suite has been needlessly blind to real playback ever since" — are live
possibilities, and the committed note forecloses investigating either,
because it reads as a closed, understood, filed fact.

**Rewritten:**

> I did not drive real-sound playback in the official test suite, and I do
> not actually know whether the crash I wrote about still exists, because I
> am an idiot who wrote a paragraph instead of a regression test.
>
> Upstream: `blanket/widgets/... ` / `blanket/main.py` plays any of 14
> bundled `.ogg` files through the same code path as every other sound; there
> is no second-class "safe" sound.
>
> Port: `test/drive_window.rb:7-11` and `test/drive_presets.rb` only ever
> call `.playing = true` on `pink-noise` (`audiotestsrc`, no
> `uridecodebin`/`pad-added` involved at all). No port test, ever, has told
> a real `.ogg` file to play and then kept running long enough to say
> whether the process survived. This audit's own one-off attempt (not a
> committed test) ran 13 real sounds for 10 seconds without a crash, which
> contradicts this file's standing claim and was never going to be caught
> by the suite as it stands, because the suite was built specifically not to
> look.
>
> The fix owed is not "stop claiming out of scope" — it is a committed,
> repeated-trial test (several runs, several real sounds, a non-trivial
> settle time, under the same `xvfb-run` + Nix shell CI will use) that
> either reproduces the segfault reliably, in which case it's a real `gap`
> with a real regression test guarding it, or it doesn't, in which case the
> standing claim in this file is wrong and the drive scripts' "works around"
> comments and `NoiseBin`-only restriction should come out. Either answer is
> fine. Not knowing, for an unknown number of rounds, is not.

## Also checked and dismissed (not violations)

- `.reports/component-inventory.md:29,322` — "by design" re: zero `.blp`
  files and twelve upstream `.ui` files having no counterpart. This is the
  Ruby house style (`ruby-gtk` skill: widgets as memoized methods, no `.ui`
  files ever) and the `component-parity` skill explicitly names this exact
  case as a **correspondence, not a gap**. Not rewritten; these are correctly
  not excuses.
- `.reports/drive-verification.md:15` — the literal string `TODO:
  GVariant({sv}) -> Ruby (NotImplementedError)` is a verbatim quote of the
  ruby-gnome binding's own exception message, not a label the port's authors
  wrote. The surrounding paragraph correctly identifies it as a binding gap,
  records the workaround, and states plainly that "no assertion was loosened
  or removed to route around it" — this is the skill's own worked example of
  how to record a binding gap honestly (in `FINDINGS.md`-equivalent prose,
  never converting the gap into a pass). Left as-is.
- `.reports/component-parity.md:13` (this audit's own report, written this
  session) — flagged by the scanner for the phrase "no Ruby equivalent", but
  the surrounding sentence is explaining the skill's own rule, not excusing a
  gap. Meta hit, not a finding.

## Stale claims found in `.reports/component-inventory.md` (false-green risk)

Separate from the two excuses above: this document's running narrative was
not kept in sync with the branch as later commits landed, and it was
committed to the repo in that state. Two sentences are now flatly false
against the current tree and would mislead anyone who reads the report
instead of the code:

- Line ~40: "The window itself is still a placeholder... No audio, no
  sounds, no bottom bar." Written before `5a86733` ("Port the main window,
  sound widgets, preferences and MPRIS"). `lib/blanket/window.rb` is 512
  lines and builds the full sound grid, volume popover, preset chooser and
  header bar — confirmed by this audit reading the file and by every drive
  script passing against it.
- Totals table: "Translated strings | ... | none". Written before `37ac2c7`
  ("Wire the gettext translation catalogue"). The port now ships 57
  languages and reaches 60 of 80 upstream messages — see
  `translation-parity.md`.

Per this task's own instruction ("a false green claim ... is the most
serious finding you can make"): a stale claim that understates progress is
less dangerous than one that overstates it, but it is still a report that
can no longer be read at face value, and it sat in the repository, committed,
across at least two further commits without correction. Fix: either delete
superseded narrative when the thing it describes changes, or date-stamp every
claim and never read a dated claim as current without checking the commit it
predates.
