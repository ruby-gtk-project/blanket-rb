# blanket-rb — drive verification

**Updated 2026-11-08** (round 2): the numbers below were stale. A fresh run
of `test/drive_window.rb`, `test/drive_presets.rb` and `test/drive_app.rb`
under `nix develop --command xvfb-run -a ruby test/drive_*.rb` this round
gets **28 + 41 + 24 = 93 checks**, all `DRIVE OK`, not the 91 this file
previously claimed — `faae9b0` added two checks to `drive_window.rb`
(the autostart portal round-trip) after this file was last written and
never updated it. The spec-suite claim below is also stale: see the
"Spec suite" section's update note. Per `.reports/accountability-ensurance.md`,
narrative claims in this file should be date-stamped or re-run each round
rather than cited as current without re-verification — this update does
that for this round; the original run's own narrative is left below,
superseded.

Original claim (round 1): ran the same three scripts and got 26 + 41 + 24 =
91 checks, all `DRIVE OK`, zero failed.

## Binding gap found while writing `test/drive_app.rb`

`Gio::DBusConnection`'s registered-object handler in `Blanket::Mpris` hands
back MPRIS's `Metadata` property as a `GLib::Variant` of type `a{sv}`. Calling
`#value` on that variant (the normal route to a Ruby value, and the one
`handle_get`'s caller would reach for) raises:

```
TODO: GVariant({sv}) -> Ruby (NotImplementedError)
```

from `gobject-introspection-4.3.9/lib/gobject-introspection/loader.rb`. This is
a ruby-gnome binding gap, not a bug in `lib/blanket/mpris.rb` — the port builds
a correct `a{sv}` GVariant (confirmed via `GLib::Variant#to_s`, which renders
the GVariant text format without going through the missing conversion, and
shows the real preset name in `xesam:title`). The drive script's check reads
`#to_s` instead of `#value` for this one property and says so in a comment;
no assertion was loosened or removed to route around it, and no check claims
to have exercised the conversion that does not exist.

## Spec suite

**Updated 2026-11-08**: the "fails with a `LoadError`" claim below is stale.
Commit `faae9b0` (after this file was written) fixed the spec suite's load
path and added `spec/blanket/define_spec.rb`. Re-run fresh this round:

```
nix develop --command ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format","progress","--require","spec_helper","spec"])'
-> 8 examples, 0 failures
```

It passes now. Scope note: the new spec file covers only `Blanket::Define`
(the sound catalogue and credits tables — a small data module with no GTK
dependency), not any widget, dialog, signal or action; that coverage is
still entirely the drive scripts' job. See `.reports/test-parity.md` for the
full, current accounting.

Original claim (round 1), left for the record and now superseded by the
above: the dev-shell banner names
`ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run([...])'`. Running
it failed before any example ran:

```
Failure/Error: require "kettle/test/rspec"
LoadError: cannot load such file -- kettle/test/rspec
```

`spec/` held only `spec_helper.rb` (which requires `kettle-test`, a dev
dependency the project's own `Gemfile` carries but the Nix `devShell` does not
bundle) and a `README.md` describing that harness's helpers. No example files
existed under `spec/` — this was kettle-dev's generated scaffolding, not a
suite the port had written tests into.
