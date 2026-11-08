# FINDINGS

Known, tracked gaps between this port and upstream that are not expected to
close without an upstream binding fix. Recorded here so they are not
silently treated as equivalent or dropped from the parity ledger.

## 1. `window-state` GSettings key retyped from a GVariant tuple to a JSON string

- **Upstream** (`data/com.rafaelmardojai.Blanket.gschema.xml.in`): the
  `window-state` key is a GVariant tuple, type `(iib)` — width (int32),
  height (int32), maximized (bool) — with description msgid "A tuple
  containing the initial width, height and maximize state of the app
  window."
- **Port** (`data/schemas/org.rubygtkproject.Blanket.gschema.xml`): the key
  is retyped `s` (string) holding a JSON-encoded 3-element array
  (default `'[-1, -1, false]'`), with a reworded description, "A JSON
  array holding the initial width, height and maximize state of the app
  window."
- **Why**: `ruby-gnome`'s `Gio::Settings` binding raises
  `NotImplementedError` converting a tuple-shaped `GVariant` in either
  direction (construction or read-back). See `lib/blanket/settings.rb`'s
  header comment and its `read_json`/`write_json` helpers, which exist
  solely to route around this.
- **Status: open, not equivalent.** The reworded description is a
  different claim about the on-disk format, not a translation of the same
  one — a JSON string in a string-typed key is not a tuple in a
  tuple-typed key, and any tool reading this GSettings schema expecting
  `(iib)` will not find it. This is a genuine `ruby-gnome` binding
  limitation, not a stylistic choice, and this port cannot close it alone.
  It stays open in the parity ledger (`.reports/translation-parity.md`,
  `.reports/component-parity.md`) rather than being marked resolved, until
  `ruby-gnome` supports round-tripping GVariant tuples through
  `Gio::Settings`.

## 2. Faking the autostart portal daemon in-process is not feasible with the current `gio2`/`gobject-introspection` bindings

Investigated this round whether the denial-alert and successful-grant
branches of `lib/blanket/preferences_dialog.rb#request_autostart` (only the
call-fails-outright path is driven, by `test/drive_window.rb` checks
16-17 — no real `xdg-desktop-portal` runs in this Nix/xvfb environment) could
be driven by faking a minimal `org.freedesktop.portal.Desktop` service
in-process, on the same session bus, answering `RequestBackground` and
emitting `Request`'s `Response` signal with a scripted response code.

Two independent, reproducible failures ruled this out:

1. **`Gio::DBusConnection#register_object`'s automatic parameter
   unmarshalling crashes on the inbound `a{sv}` `options` argument** —
   the same `NotImplementedError: TODO: GVariant({sv}) -> Ruby` already
   documented for MPRIS's `Metadata` property (see
   `.reports/drive-verification.md`), but on an *inbound* method-call
   argument this time, not an outbound property value. The exception
   propagates out through the native `Gio::Application#run` call and
   kills the whole process — not something a `rescue` inside the handler
   block can catch, since it is raised while GI marshals the arguments
   before the block ever runs.
2. **Routing around that with `Gio::DBusConnection#add_filter`** (which
   hands back the message's raw, un-auto-converted `GVariant` body,
   sidestepping the broken `a{sv}` conversion by reading it as text via
   `#print` instead, the same workaround `test/drive_app.rb` already
   uses for MPRIS) hits a second, different crash: filter callbacks run
   on a GDBus worker thread, and invoking into Ruby from it without that
   thread ever being registered with `rbgutil_start_callback_dispatch_thread()`
   aborts the process outright — a `Ruby/GLib2-ERROR` followed by a core
   dump, confirmed by direct reproduction in this session. This is the
   same general class of bug as Finding 3 below (a GStreamer/GLib worker
   thread calling into Ruby that never registered it), just hit through
   D-Bus instead of GStreamer.

**Status: not attempted as a shipped test.** A test that reliably crashes
the process is worse than no test — it would read as "driven" while
actually proving nothing and breaking CI. The denial-alert and
grant branches stay read-verified only, as before, but now on the basis
of a concrete, reproduced investigation rather than an assumption that it
would be easy. If `ruby-gnome` ever supports round-tripping `a{sv}`
GVariants and/or registers worker threads for Ruby callback dispatch by
default, this is worth revisiting.

## 3. Real, file-backed sound playback (`LoopBin`/`uridecodebin`) hangs — confirmed, not merely suspected

`test/drive_window.rb` and `test/drive_presets.rb` have, across at least two
audit rounds before this one, only ever told a synthetic `NoiseBin`
(`pink-noise`, `audiotestsrc`, no `uridecodebin`) to play, with a comment
naming a suspected-but-never-confirmed thread-safety crash in
`uridecodebin`'s `"pad-added"` signal, which GStreamer fires from a
streaming thread Ruby never registered with the GVL.

**Confirmed this round**, by direct, repeated, reproducible testing — see
`test/drive_real_sounds.rb`, a committed regression test that forks each
sound's play attempt with a hard wall-clock budget so a hang cannot hang
the test suite itself:

- Of 12 distinct real, bundled `.ogg` files tried (`rain`, `wind`,
  `fireplace`, `birds`, `waves`, `stream`, `storm`, `city`, `boat`,
  `coffee-shop`, `summer-night`, `train`) across 2 trials — 24 attempts —
  **19 hung for the entire 16-second hard budget and only 5 survived**
  (`birds`, `city` x2, `coffee-shop`, `summer-night`). This is a strong
  majority failure rate (79%), not a deterministic 100% — consistent with
  an intermittent thread-race rather than a bug that fires every time,
  which matches the "suspected thread-safety crash" framing exactly. A
  bug this severe and this frequent is not something a healthy app can
  ship with, intermittent or not.
- A separate, earlier run of an unbounded (non-forked) version of the same
  test did not merely hang: it terminated with GStreamer's own built-in
  signal handler dumping a native backtrace and `/proc/self/maps` to
  stderr — i.e. a real SIGSEGV, not just a stall — confirmed by the
  presence of hundreds of lines of raw memory-map output with no
  corresponding script output (the crash happened before Ruby's
  block-buffered stdout from the test script was ever flushed; the
  native crash handler's unbuffered writes went straight through).

This is a real, severity-1, reproducible defect in
`lib/blanket/audio/bins.rb`'s `LoopBin`/`SoundBin` pipeline-callback wiring,
not a benign quirk — it means the port's core "play an ambient sound"
feature does not work today for 13 of its 14 bundled sounds (every one
backed by a real file; only the two noise generators are unaffected). It is
tracked as an open defect in `.reports/test-parity.md` and
`.reports/component-parity.md`, guarded by `test/drive_real_sounds.rb`
rather than left as an unconfirmed suspicion. `test/drive_window.rb`'s
avoidance of real-sound playback is correct and stays, now backed by
reproduced evidence instead of suspicion.
