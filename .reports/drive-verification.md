# blanket-rb — drive verification

Ran `test/drive_window.rb`, `test/drive_presets.rb` and the new
`test/drive_app.rb` under `nix develop --command xvfb-run -a ruby test/drive_*.rb`.
All three end `DRIVE OK` with zero failed checks (26 + 41 + 24 = 91 checks).

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

The dev-shell banner names
`ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run([...])'`. Running
it fails before any example runs:

```
Failure/Error: require "kettle/test/rspec"
LoadError: cannot load such file -- kettle/test/rspec
```

`spec/` holds only `spec_helper.rb` (which requires `kettle-test`, a dev
dependency the project's own `Gemfile` carries but the Nix `devShell` does not
bundle) and a `README.md` describing that harness's helpers. No example files
exist under `spec/` — this is kettle-dev's generated scaffolding, not a suite
the port has written tests into. Fixing the `LoadError` would still run zero
examples, so there is nothing to gate on here; it is recorded for whoever next
touches the Nix shell or wants to start writing real unit specs.
