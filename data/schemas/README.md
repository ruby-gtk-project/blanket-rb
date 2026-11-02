# GSettings schemas

`org.rubygtkproject.Blanket.gschema.xml` holds the app's schema and the
relocatable per-preset schema, ported from
`data/com.rafaelmardojai.Blanket.gschema.xml.in` upstream.

GSettings reads the compiled form, so `gschemas.compiled` is committed next to
the source and the dev shell points `GSETTINGS_SCHEMA_DIR` at this directory.
After editing the XML, recompile it:

```sh
nix develop --command glib-compile-schemas data/schemas
```

The Nix package compiles the schema itself at install time and ignores the
committed binary.
