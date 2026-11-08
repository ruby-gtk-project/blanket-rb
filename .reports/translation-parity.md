# Translation parity — blanket-rb

| | |
|---|---|
| Upstream | `origin/master` @ `7586dbc` |
| Port | `ruby` @ `faae9b0` |
| Domain | `blanket` (confirmed: `lib/blanket/i18n.rb` binds `"blanket"`, `locale/*/LC_MESSAGES/blanket.mo` matches) |
| Upstream messages (source, excl. po/) | 80 distinct `(ctxt, id)` keys |
| Port messages (source, excl. po/) | 114 distinct `(ctxt, id)` keys |
| Ported (by msgid, ignoring the one ctxt-scanner artifact) | 77 of 80 |
| Real gaps | **3** (down from 19 last round) |
| Upstream languages | 57 `.po` files + `blanket.pot`, matching `LINGUAS` |
| Languages shipped by the port | 57 `.mo` files, same set |

Census re-run fresh this session with
`.claude/skills/translation-parity/scripts/msgid-census.sh` against fresh
`origin/master` and `ruby`-branch worktrees, filtered to exclude `po:`-kind
rows per the skill (a `.po` lists deleted msgids too and overcounts).

## 16 of the 19 prior gaps are closed

Last round's 19 gaps traced to three things: the missing autostart-error
dialog (4 strings), the missing preset-chooser tooltip (1 string), and two
whole missing files — the desktop entry (1 string) and the metainfo (11
strings). This round (`b815019`) built the autostart portal flow, the
tooltip, the desktop file and most of the metainfo. Re-running the census
confirms all 16 of those msgids now resolve on the port side:

- `Authorization failed`, the long explanation, `Ok`, `The autostart
  request failed.` — present (`lib/blanket/preferences_dialog.rb`).
- `Presets Menu` — present (`lib/blanket/preset_chooser.rb:77`).
- `Concentrate;Focus;Noise;Productivity;Sleep;` (desktop Keywords) —
  present, byte-identical (`data/org.rubygtkproject.Blanket.desktop.in`).
- `Add custom sounds`, `Also can help you to fall asleep in a noisy
  environment.`, `Auto start in background`, `Features:`, `Improve focus
  and increase your productivity by listening to different ambient
  sounds`, `Included Sounds in the App:`, `Listen to ambient sounds`,
  `MPRIS integration`, `Save presets` — all present in
  `data/org.rubygtkproject.Blanket.metainfo.xml.in`.

## Round 2: 2 of the 3 gaps closed; 1 remains open (binding limitation, tracked in `FINDINGS.md`)

| msgid | Upstream source | Status |
|---|---|---|
| `A tuple containing the initial width, height and maximize state of the app window.` | `data/com.rafaelmardojai.Blanket.gschema.xml.in` | **still open.** port's `window-state` gschema key is retyped (`s`/JSON, not GVariant tuple `(iib)` — ruby-gnome's `Gio::Settings` binding cannot round-trip the tuple type) and its `<description>` was necessarily reworded ("A JSON array holding...") to match. A genuine binding limitation, not something to treat as equivalent — see `FINDINGS.md`'s first entry for the full account, now tracked there explicitly rather than only in this table |
| `The default screen in light theme` | `data/com.rafaelmardojai.Blanket.metainfo.xml.in.in` (screenshot caption) | **closed this round.** `data/org.rubygtkproject.Blanket.metainfo.xml.in` now has a `<screenshots>` block carrying this caption |
| `The default screen in dark theme` | same file, same block | **closed this round**, same `<screenshots>` block |

The one remaining gap is named and located, and is not excused as
equivalent to the upstream msgid it replaces. See
`component-identification.md` and `component-parity.md` for the same two
findings recorded against their components.

## One scanner artifact (not a real gap) — unchanged from last round

`translator-credits`: the upstream `.blp` has a translator comment
immediately above the string, which the census folds into the msgctxt
column on the upstream side only, so a strict `(ctxt,id)` diff shows it as
missing. Comparing by msgid alone (ignoring ctxt) shows it present on both
sides — confirmed directly in `lib/blanket/about_dialog.rb:42` this session.
Counted as matched in the headline numbers above, not as a gap.

## `!unresolved` marker — unchanged from last round

`blanket/mpris.py:169` reaches a dynamic string
(`_(Settings.get().active_preset_name)`) through an expression, not a
literal, which the census correctly flags rather than silently dropping or
silently matching. Arguably an upstream bug (a user's own preset name run
through `_()`), not a real catalogue message. Noted, not counted either
direction.

## New this round — the autostart gschema key gained a description upstream never had

`data/schemas/org.rubygtkproject.Blanket.gschema.xml`'s `autostart` key now
carries a `<summary>Start the app on login</summary>` and a
`<description>Whether the app asks the portal to autostart it when the
session begins.</description>`. Upstream's `com.rafaelmardojai.Blanket.
gschema.xml.in` has **no** summary or description on this key at all —
confirmed by direct read, this session. This is new translatable text with
no upstream counterpart, which is fine (it is not a mistranslation of
anything upstream says) but it means these two strings join the 39-ish
"extra" set below rather than the matched set, and nobody should mistake
their presence for a ported upstream string.

## Extra (untranslated, port-only) messages

Not counted against parity, not free — every one is English-only until
translated. 114 port keys − 77 matched (by msgid) − 1 artifact already
counted as matched = roughly 36 genuinely port-only strings (new widget
labels, the new gschema description above, etc.), consistent with last
round's estimate. Not itemised exhaustively; still flagged as warranting its
own pass before claiming full coverage.

## Checks that did run

- `diff <(ls po/*.po) <(cat po/LINGUAS)`: 57/57, matching on both sides,
  unchanged this round (neither side touched `po/`).
- Domain confirmed by direct inspection of `lib/blanket/i18n.rb` and
  `locale/*/LC_MESSAGES/blanket.mo`.
- The autostart portal strings, the tooltip, the desktop file and the
  metainfo additions were all independently located in the port's source
  this session, not taken from the commit message's own description of
  itself.

## Checks not run (say so plainly)

- `msgfmt -c` catalogue validation — `msgfmt` not installed in this
  environment, same as last round.
- A live non-English run (`LANGUAGE=de LC_ALL=de_DE.UTF-8 xvfb-run ruby
  exe/blanket`, asserting a known translated string on screen) was **not
  executed this round either**. The claim that this was done in some past
  session is still unverified by any report in this repository and should
  not be treated as proven until someone runs it and records the output.

## Verdict

Round 1: 19 gaps down to 3. **Round 2: 3 gaps down to 1.** The metainfo's
two screenshot-caption msgids now have a home — `data/org.rubygtkproject.
Blanket.metainfo.xml.in`'s new `<screenshots>` block carries both,
verbatim, as upstream's captions — closing 2 of the 3. The one that
remains, the `window-state` gschema tuple-to-JSON retyping, is a genuine
`ruby-gnome` binding limitation (confirmed, not assumed — see
`FINDINGS.md`'s first entry) and stays open rather than being waved through
as an equivalent rewording. Not full translation parity — 1 gap open, plus
the live-locale claim still unverified — but closing real ground this
round, independently re-verified rather than carried forward on faith.
