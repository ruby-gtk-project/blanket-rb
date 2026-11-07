# Translation parity — blanket-rb

| | |
|---|---|
| Upstream | `origin/master` @ `7586dbc` |
| Port | `ruby` @ `37ac2c7` |
| Domain | `blanket` (confirmed: `lib/blanket/i18n.rb` binds `"blanket"`, and `locale/*/LC_MESSAGES/blanket.mo` matches) |
| Upstream messages (source, excl. po/) | 80 distinct `(ctxt, id)` keys |
| Port messages (source, excl. po/) | 98 distinct `(ctxt, id)` keys |
| Ported (by msgid) | 60 of 80 |
| Gaps (by msgid) | 19 real + 1 scanner artifact |
| Extra (untranslated, port-only) | 39 |
| Upstream languages | 57 `.po` files + `blanket.pot`, matching `LINGUAS` (57 entries) |
| Languages shipped by the port | 57 `.mo` files under `locale/*/LC_MESSAGES/blanket.mo`, same language set |
| Checks not run | `msgfmt -c` validation (not installed in this environment); live non-English screen check (not run this pass — see below) |

Census run with `.claude/skills/translation-parity/scripts/msgid-census.sh`
against `origin/master` and `origin/ruby` worktrees, this session, not taken
from any prior report.

## The headline claim this gate was ready to make, and why it is wrong

The committed `.reports/component-inventory.md` totals table (written before
`37ac2c7`) says "Translated strings: 87 msgids, 57 `po/*.po` locales | none".
That line is now **stale**: the i18n commit wired `_()`/`n_()` calls through
eleven files and copied upstream's whole `po/` + `LINGUAS` across. 57/57
languages ship, the domain matches, and 60 of upstream's 80 source-level
messages are reachable in the port by exact msgid. This is real, substantial
work. It is not, however, 80/80, and the gap is not evenly distributed — see
below.

## 19 confirmed gaps

Comparing `(ctxt,id)` keys extracted from source only (excluding `po/`, per
the skill — a `.po` lists deleted msgids too and would overcount):

| msgid | Upstream source | Why it's missing from the port |
|---|---|---|
| `Add custom sounds` | `data/com.rafaelmardojai.Blanket.metainfo.xml.in.in` | metainfo file does not exist in the port at all |
| `Also can help you to fall asleep in a noisy environment.` | metainfo | ditto |
| `A tuple containing the initial width, height and maximize state of the app window.` | `data/com.rafaelmardojai.Blanket.gschema.xml.in` | port's gschema key is retyped (`s`/JSON, not a GVariant tuple — ruby-gnome can't convert `(iib)`) and its `<description>` was necessarily reworded to match; the exact upstream sentence has no home |
| `Authorization failed` | `blanket/preferences.py:77` | the whole autostart-portal error dialog was never built — see `component-parity.md` Gap 1 |
| `Autostart Blanket in background.` | `blanket/preferences.py` (gschema description for the `autostart` key, upstream wording) | port's gschema description for this key was reworded (see retyping note above) |
| `Auto start in background` | metainfo (feature-list item) | metainfo file missing |
| `Concentrate;Focus;Noise;Productivity;Sleep;` | `data/com.rafaelmardojai.Blanket.desktop.in.in` (`Keywords`) | desktop file does not exist in the port at all |
| `Features:` | metainfo | metainfo file missing |
| `Improve focus and increase your productivity by listening to different ambient sounds` | metainfo | metainfo file missing |
| `Included Sounds in the App:` | metainfo | metainfo file missing |
| `Listen to ambient sounds` | metainfo | metainfo file missing (note: this is distinct from the port's about-dialog comment `Listen to different sounds`, which is a different, correctly-ported string) |
| `Make sure Blanket has permission to run in the background in Settings → Applications → Blanket and try again.` | `blanket/preferences.py:79` | same missing autostart-error dialog as `Authorization failed` above |
| `MPRIS integration` | metainfo (feature-list item) | metainfo file missing |
| `Ok` | `blanket/preferences.py:82` | same missing autostart-error dialog |
| `Presets Menu` | `data/resources/window.blp:22` (`$PresetChooser` tooltip-text) | tooltip never set in `lib/blanket/preset_chooser.rb` — see `component-parity.md` Gap 2 |
| `Save presets` | metainfo (feature-list item) | metainfo file missing |
| `The autostart request failed.` | `blanket/preferences.py:89` | same missing autostart-error dialog |
| `The default screen in dark theme` | metainfo (screenshot caption) | metainfo file missing |
| `The default screen in light theme` | metainfo (screenshot caption) | metainfo file missing |

16 of the 19 trace to two whole files the port never created
(`metainfo.xml.in.in`, `desktop.in.in`) or one file whose keys were
necessarily retyped (`gschema.xml.in`, 3 strings). The remaining 4
(`Authorization failed`, the long explanation, `Ok`, `The autostart request
failed.`) trace to one behaviour the port never built — see
`component-parity.md` Gap 1 and `accountability-ensurance.md`.

## One scanner artifact (not a real gap)

`translator-credits` appears to be a gap in a raw `(ctxt,id)` diff because
the upstream `.blp` has a translator comment
(`#. Add your names here, do not remove previous names!`) immediately above
the string, which `msgid-census.sh` folds into the msgctxt column on the
upstream side; the port's Ruby call site has no such adjacent comment, so its
ctxt comes back `-`. Comparing by msgid alone (ignoring ctxt) shows
`translator-credits` present on both sides — confirmed in
`lib/blanket/about_dialog.rb:42`. This is recorded here rather than silently
fixed in the shared script, per the skill's instruction to say when the
scanner, not the port, is what's wrong.

## `!unresolved` marker

Upstream's `blanket/mpris.py:169` reaches a dynamic string through
`_(Settings.get().active_preset_name)` — an expression, not a literal — which
the census correctly flags `!unresolved` rather than silently dropping. This
is upstream's own preset name interpolated as a literal translation call,
which is arguably a bug in upstream (a user's custom preset name run through
`_()`), not a catalogue message at all. Noting it rather than counting it
either way.

## 39 extra (untranslated) port messages

Not counted against parity, and not free — every one is English-only until
someone translates it. The bulk are new UI strings for widgets the Ruby port
builds that upstream expresses in a `.blp` the census doesn't attribute to
these exact bytes (e.g. button labels built inline), plus a handful of
genuinely new strings. Not itemised exhaustively here; flagged as a thing to
audit individually before claiming full translation coverage, since a large
extra set this size relative to the 80-message upstream catalogue warrants
its own pass.

## Checks that did run

- `diff <(ls po/*.po) <(cat po/LINGUAS)` equivalent: 57 `.po` files, 57
  `LINGUAS` entries, matching (upstream and port both).
- Domain confirmed by direct inspection of `lib/blanket/i18n.rb` and the
  `locale/*/LC_MESSAGES/blanket.mo` filenames — `blanket`, matching upstream.
- Drive-verification's own claim ("a German catalogue round-trips a
  translated string through the newly bound text domain") was **not**
  independently re-verified by this audit — see Checks not run below.

## Checks not run (say so plainly, per the skill)

- `msgfmt -c` catalogue validation — `msgfmt` is not installed in this
  environment (`which msgfmt` → not found). Cannot confirm every `.po`
  compiles cleanly; relying on the committed `.mo` files having been built
  correctly by whoever ran `rake gettext:mo`.
- A live non-English run (`LANGUAGE=de LC_ALL=de_DE.UTF-8 xvfb-run ruby exe/blanket`,
  asserting a known string on screen) was **not executed by this audit pass**.
  The previous commit's message claims this was done ("a German catalogue
  round-trips a translated string through the newly bound text domain") but
  that claim rests on a prior session's work, not on anything this audit
  re-ran. Per the gate this task sets ("a false green ... is the most serious
  finding"): this claim is unverified by this report and should not be
  treated as proven until someone re-runs it and records the output.

## Verdict

Not translation parity. 60/80 messages, 57/57 languages shipped, domain
correct — real, substantial progress — but 19 real gaps remain, concentrated
in two missing data files and one missing dialog, plus one live-locale claim
this audit could not independently confirm.
