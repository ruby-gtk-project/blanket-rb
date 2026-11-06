# blanket — upstream component inventory

Survey of `origin/master` (Blanket, Python + PyGObject + GTK4/libadwaita +
GStreamer) against `lib/` on the `ruby` branch, for the full-parity Ruby port.

Method: the `component-identification` skill. Upstream carries blueprint UI, so
the twelve `data/resources/*.blp` files were read first — they are the real
widget trees, the CSS classes and the signals — then every Python module that
backs one, plus the GSettings schema, the GResource manifest and `po/`.

Re-surveyed after `2dffcf3 Port the settings, presets and app dialogs`; the
present/missing column below reflects the branch at that commit.

**Re-surveyed again** at the current tip of `ruby`: `lib/blanket/sound.rb`
(252 lines), `lib/blanket/main_player.rb` (405 lines) and
`lib/blanket/audio/bins.rb` (241 lines) have since landed — the whole
GStreamer player stack is now ported — and `flake.nix` now carries a
`gstStack` (`gstreamer`, `gst-plugins-base`, `gst-plugins-good`) feeding both
`buildInputs` and `typelibPath`/`GI_TYPELIB_PATH`, plus
`GST_PLUGIN_SYSTEM_PATH_1_0`, and a custom `gstreamer` gem override for its C
extension. Blocker 1 below is resolved; the "Non-widget units" table and
blockers section are corrected in place rather than re-run from scratch.

## Totals

| | Upstream | `ruby` branch |
|---|---|---|
| UI units (blueprint template / named root / app class) | 14 | 5 (application shell, preset chooser, preset row, preset dialog, shortcuts, about) |
| Blueprint files | 12 | 0 (by design — widgets are memoized methods) |
| Python modules | 20 | 13 Ruby files (+ `sound.rb`, `main_player.rb`, `audio/bins.rb` since the first survey) |
| Distinct widget types | ~30 | ~16 |
| CSS classes applied | 15 (`accent`, `caption-heading`, `circular`, `devel`, `error`, `flat`, `menu`, `playpause`, `preset-row`, `selected`, `sound-item`, `sound-view`, `suggested-action`, `volume-row`, `volume-separator`) | 5 (`menu`, `preset-row`, `selected`, `flat`, `circular`, `suggested-action`) |
| Stylesheet | `data/resources/style.css`, 17 rules | `lib/blanket/style.css`, 17 rules — **ported whole** |
| GActions | 14 (`app.*` ×12, `win.*` ×2) | 6 (`app.quit`, `app.about`, `app.shortcuts`, `app.add-preset`, `app.background-playback`, `win.close`) |
| Accelerators | 6 | 3 (`<Control>q`, `<Control>question`, `<Control>w`) |
| GSettings schemas | 2 (app + `.preset`), 13 + 4 keys | **both present**, same key names, under `org.rubygtkproject.Blanket`, compiled to `data/schemas/` |
| Assets | 16 symbolic icons, 14 `.ogg` sounds in GResource | **all present on disk** (`data/icons/hicolor/scalable/emblems`, `data/sounds`) |
| Translated strings | 87 msgids, 57 `po/*.po` locales | none |

The window itself is still a placeholder: `lib/blanket/application.rb` presents
an `Adwaita::ApplicationWindow` holding an `Adwaita::ToolbarView`, a header bar
with the real `PresetChooser` and main menu, and an `Adwaita::StatusPage` where
the sound grid belongs. No audio, no sounds, no bottom bar.

## Path convention

The pilot port (`gnome-contacts-rb`) is flat `lib/<thing>.rb`. This fork is
packaged as the `blanket-rb` gem and already has `lib/blanket.rb` +
`lib/blanket/application.rb`, with `exe/blanket` doing `require "blanket"`.
Targets below therefore keep this fork's existing namespace,
`lib/blanket/<thing>.rb`, one upstream unit per file.

---

## lib/blanket/application.rb — the application object: actions, accelerators, MPRIS, power monitor

Upstream: `blanket/main.py`. **Partial** — exists with the window shell, the
primary menu, six actions, three accelerators and the CSS provider. Missing:
the `--hidden` command-line option, the power-profile monitor, the playback
actions, the sound actions, the dark-mode fallback and the full accelerator set.

| Thing | × | Present | Notes |
|---|---:|---|---|
| `Gtk::Application` (upstream `Adw.Application`) | 1 | yes | upstream sets `HANDLES_COMMAND_LINE`, `resource_base_path` and `PULSE_PROP_application.icon_name`; the port sets none of these. `Adwaita::Application` is broken in the Ruby bindings, so the app object is `Gtk::Application` |
| `--hidden` command-line option | 1 | no | starts the window hidden; `do_command_line` |
| `Gio::PowerProfileMonitor` | 1 | no | `notify::power-saver-enabled` → pause playback + show power toast |
| `Adwaita::StyleManager` | 1 | partial | reachable as `style_manager`; the force-dark fallback for systems without colour schemes is not wired |
| Signal `shutdown` | 1 | partial | the port saves presets; upstream also stops the player |
| Signal `close-request` on the window | 1 | yes | hide when background playback is on, else save window state and quit |
| `Gtk::CssProvider` | 1 | yes | loads `lib/blanket/style.css` at `PRIORITY_APPLICATION` |

Actions installed upstream (names are literals; the `space` accelerator is
removed while a text-entry dialog is open and restored on close —
`set_space_accel` / `unset_space_accel`):

| Action | Kind | Accelerator | Present |
|---|---|---|---|
| `app.quit` | simple | `<Ctl>q` | yes |
| `app.about` | simple | — | yes |
| `app.preferences` | simple | `<Ctl>comma` | no |
| `app.background-playback` | stateful (boolean) | — | yes |
| `app.playpause` | simple | `<Ctl>m`, `space` | no |
| `app.play` | simple | — | no |
| `app.add-preset` | simple | — | yes |
| `app.reset-volumes` | simple | — | no |
| `app.open` | simple | `<Ctl>o` | no |
| `app.remove-sound` | simple, param `u` | — | no |
| `app.rename-sound` | simple, param `u` | — | no |
| `win.close` | simple | `<Ctl>w` | yes |
| `win.hide-inactive` | stateful (boolean) | `<Ctl>h` | no |
| `app.shortcuts` | — (never installed upstream) | — | **installed in the port**, with `<Control>question` |

## lib/blanket/window.rb — the main window: sound grid, bottom bar, menus

Upstream: `blanket/window.py` + `data/resources/window.blp`. **Missing** — the
window exists only as the shell inside `application.rb`, and must move into its
own file when the grid and bottom bar land.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adwaita::ApplicationWindow` | 1 | `devel` (only when APP_ID ends `Devel`) | `close-request` | 360×294 request; 520×600 default; `window-state` GSetting restores size/maximized |
| `Adwaita::Breakpoint` | 1 | — | `apply`, `unapply` | `max-width: 360px` → hides the header title when >1 preset |
| `Adwaita::ToolbarView` | 1 | — | — | `bottom-bar-style: raised` |
| `Adwaita::HeaderBar` | 1 | — | — | hosts `PresetChooser` (start) and the main `MenuButton` (end) |
| `Gtk::MenuButton` | 3 | `circular` (2 of 3) | — | main menu (`open-menu-symbolic`), volume menu (`audio-speakers-symbolic`, direction up), sounds menu (`view-more-symbolic`, direction up); tooltips "Main Menu" / "Volume Menu" / "Sounds Menu" |
| `Adwaita::ToastOverlay` | 1 | — | — | hosts the power toast |
| `Gtk::ScrolledWindow` | 2 | — | — | the grid; the volume list (max height 320) |
| `Gtk::FlowBox` | 1 | `sound-view` | `child-activated` | single-click activate, homogeneous, 12px spacing; `bind_model` over a `Gtk::FilterListModel` wrapped in `DummyItemModel` |
| `Gtk::ActionBar` | 1 | — | — | bottom bar, centre `Gtk::Box` spacing 24 |
| `PlayPauseButton` | 1 | see its own unit | — | `action-name: app.playpause` |
| `Gtk::PopoverMenu` (`volumes`) | 1 | — | `closed` → mute sounds at volume 0 | width 250; menu model `volume-menu` with a `custom: "volumes"` slot |
| `Gtk::Scale` (master volume) | 1 | — | adjustment bound bidirectionally to `MainPlayer#volume` | no value drawn |
| `Gtk::Box` (`volume_box`) | 1 | — | — | hidden when no sound is playing — **empty state** |
| `Gtk::Separator` | 1 | `volume-separator` | — | |
| `Gtk::ListBox` (`volume_list`) | 1 | — | — | `bind_model` → `VolumeRow` per playing sound |
| `Gtk::SizeGroup` (`labels_group`) | 1 | — | — | vertical, over every sound-item label |
| `Gtk::Adjustment` | 1 | — | — | 0..1 step 0.01 |
| `Adwaita::Toast` (`power_toast`) | 1 | — | `action-name: app.play` | "Paused to save power" / "_Resume Playing", timeout 0 — **error/notice state** |
| `Gtk::CustomFilter` | 2 | — | — | hide-inactive filter on the grid; playing filter on the volume list |
| `Gtk::FileDialog` | 1 | — | `open_multiple` | title "Open audio"; 6 filters (Supported audio files, Ogg, FLAC, WAV, MP3, AAC) |

Menus defined in `window.blp` (all land in this file):

| Menu | Items |
|---|---|
| `primary-menu` | "Keep Playing when Closed" (`app.background-playback`); "Preferences", "Keyboard Shortcuts", "About Blanket"; "Quit" |
| `volume-menu` | `custom: "volumes"` slot; "Reset Sounds" (`app.reset-volumes`) |
| `more-menu` | "Hide Inactive Sounds" (`win.hide-inactive`), "Save as New Preset…" (`app.add-preset`); "Add Sound…" (`app.open`) |

The port currently carries `primary-menu` in `application.rb`, without its
"Preferences" item and with "Save as New Preset…" (upstream's `more-menu`)
folded in so the action reaches the preset chooser. Both menus belong in this
unit once it exists.

Repeaters: the grid is one `SoundItem` per sound in `MainPlayer` (14 bundled + N
custom) plus one dummy "Add…" tile; the volume list is one `VolumeRow` per
playing sound. Conditional: `presets_chooser` is visible only when more than
one preset exists; `volume_box` only when something plays.

## lib/blanket/play_pause_button.rb — the big round play/pause button

Upstream: `blanket/widgets/playpause.py`. **Missing.**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk::Button` | 1 | `playpause`, `circular`, `suggested-action` | `notify::playing` | icon swaps `media-playback-pause-symbolic` / `media-playback-start-symbolic`; `playing` property bound from `MainPlayer` |

## lib/blanket/preset_chooser.rb — the preset menu button in the header bar

Upstream: `blanket/widgets/preset_chooser.py` + `data/resources/preset-chooser.blp`. **Present** (136 lines).

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk::MenuButton` | 1 | — | `notify::selected` | `always-show-arrow`; tooltip "Presets Menu" |
| `Gtk::Label` | 1 | — | — | bound to the selected preset's name, ellipsized |
| `Gtk::Popover` | 1 | `menu` | — | width 250, max content 300×400 |
| `Gtk::ScrolledWindow` | 1 | — | — | propagates natural size |
| `Gtk::ListBox` (`presets_list`) | 1 | — | `row-activated` | `bind_model` over a `Gio::ListStore` of `Preset` |

Repeater: one `PresetRow` per preset. Also listens to `Settings` `preset-changed`.

## lib/blanket/preset_row.rb — one preset in the preset popover

Upstream: `blanket/widgets/preset_row.py` + `data/resources/preset-row.blp`. **Present** (113 lines).

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk::ListBoxRow` | 1 | `preset-row`, `selected` (dynamic, added on `notify::selected`) | `notify::selected` | `.preset-row.selected label` is bold |
| `Gtk::Box` | 3 | — | — | row body, button group |
| `Gtk::Label` (`name`) | 1 | — | — | bound to `Preset#name`, max 16 chars |
| `Gtk::Image` | 1 | — | — | `object-select-symbolic`, visible when selected |
| `Gtk::Button` (`rename_btn`) | 1 | `flat`, `circular` | `clicked` → popdown + `PresetDialog(preset)` | `document-edit-symbolic`, tooltip "Rename Preset"; visible only for custom presets |
| `Gtk::Button` (`delete_btn`) | 1 | `flat`, `circular` | `clicked` → remove preset, reselect default | `edit-delete-symbolic`, tooltip "Delete Preset"; custom presets only |

## lib/blanket/preset_dialog.rb — "New Preset" / "Edit Preset"

Upstream: `blanket/widgets/preset_dialog.py` + `data/resources/preset-dialog.blp`. **Present** (162 lines).

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adwaita::Dialog` | 1 | — | `realize` → unset space accel; `closed` → restore it | 360×148; focus widget is the entry. The accel juggling has nothing to unset until `app.playpause` exists |
| `Adwaita::ToolbarView` | 1 | — | — | |
| `Adwaita::HeaderBar` | 1 | — | — | no window buttons either side |
| `Adwaita::WindowTitle` | 1 | — | — | title bound to the dialog title; subtitle = preset name when editing |
| `Gtk::Button` (Cancel) | 1 | — | `clicked` → `_on_cancel_clicked` | |
| `Gtk::Button` (`accept_btn`, "Save") | 1 | `suggested-action` | `clicked` → create or rename | starts insensitive |
| `Adwaita::PreferencesPage` / `PreferencesGroup` | 1 each | — | — | |
| `Adwaita::EntryRow` (`name_entry`) | 1 | — | `changed` → `_on_entry_changed` | title "Preset Name"; gates `accept_btn` on a non-blank, changed name |

Two states in one file: no preset → title "New Preset", Save creates; a preset →
title "Edit Preset", Save renames.

## lib/blanket/sound_item.rb — one sound tile in the grid

Upstream: `blanket/widgets/sound_item.py` + `data/resources/sound-item.blp`. **Missing.**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk::FlowBoxChild` | 1 | `sound-item`, `error` (dynamic, on `failed`) | `notify::playing`, `notify::failed` | width request 100; tooltip bound to `error_message` |
| `Gtk::Box` | 1 | — | — | vertical, spacing 6 |
| `Gtk::Image` (`icon`) | 1 | `accent` (dynamic, while playing) | — | pixel size 64; `blanket-<name>-symbolic`, `blanket-sound-wave-symbolic` for custom sounds, `blanket-add-symbolic` for the dummy tile |
| `Gtk::Label` (`label`) | 1 | — | — | 2 lines, wrap, centred, height 40; in the window's size group |
| `Gtk::Scale` (`volume`) | 1 | — | adjustment bound bidirectionally to `Sound#saved_volume`; sensitivity bound to `playing` | hidden until a sound is attached; styled to a bare progress bar by `style.css` |
| `Gtk::GestureClick` | 1 (controller) | — | `pressed` (button 3) | right-click opens `SoundContextMenu` pointing at the click |
| `Gtk::Adjustment` | 1 | — | — | 0..1 step 0.01 |

**Empty state:** the last tile has no sound — title "Add…", icon
`blanket-add-symbolic`, and activating it opens the file dialog. This is what
`blanket/utils.py`'s `DummyItemModel` exists for.

## lib/blanket/volume_row.rb — one playing sound in the volume popover

Upstream: `blanket/widgets/volume_row.py` + `data/resources/volume-row.blp`. **Missing.**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk::ListBoxRow` | 1 | `volume-row` | — | not selectable; `.volume-row:hover`, `.volume-row label` and `.volume-row scale` are styled in `style.css` |
| `Gtk::Box` | 1 | — | — | vertical |
| `Gtk::Label` (`title`) | 1 | `caption-heading` | — | ellipsize end, `xalign: 0`, bound to the row's `title` property |
| `Gtk::Scale` (`volume`) | 1 | — | adjustment bound bidirectionally to the row's `volume` property (`no-sync-create`) | hexpand, no value drawn |
| `Gtk::Adjustment` | 1 | — | — | 0..1 step 0.01 |

The Python side is nothing but the two GObject properties the window binds per
playing sound; all of the behaviour is the blueprint's bidirectional binding.

## lib/blanket/sound_context_menu.rb — right-click menu on a sound tile

Upstream: `blanket/widgets/sound_context_menu.py` + `data/resources/sound-context-menu.blp`. **Missing.**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk::PopoverMenu` | 1 | — | `show` → `on_opened`; `closed` → unbind | no arrow, position right, width 200 |
| `Gtk::Scale` (`volume`) | 1 | — | bound bidirectionally to `Sound#saved_volume`; sensitivity = `!failed` | in the `custom: "volume"` slot |
| `Gtk::Adjustment` | 1 | — | — | 0..1 step 0.01 |
| `Gio::Menu` section (custom sounds only) | 1 | — | — | "Rename" → `app.rename-sound(u)`, "Remove" → `app.remove-sound(u)`, appended at runtime |

Conditional: the Rename/Remove section exists only for custom sounds.

## lib/blanket/sound_rename_dialog.rb — "Rename Sound"

Upstream: `blanket/widgets/sound_rename_dialog.py` + `data/resources/sound-rename-dialog.blp`. **Missing.**

Same widget tree as `PresetDialog` (dialog, toolbar view, header bar with no
window buttons, `Adwaita::WindowTitle`, Cancel, `suggested-action` Save,
preferences page/group, `Adwaita::EntryRow` titled "Sound Name"). Differences:
title is always "Rename Sound", the subtitle is the current sound name, and
`accept_btn` is additionally gated against a name already in
`Settings#custom_audios`.

## lib/blanket/preferences_dialog.rb — Preferences

Upstream: `blanket/preferences.py` + `data/resources/preferences.blp`. **Missing** — and `app.preferences` is not installed, so the menu item is absent too.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adwaita::PreferencesDialog` | 1 | — | — | |
| `Adwaita::PreferencesPage` | 1 | — | — | |
| `Adwaita::PreferencesGroup` | 2 | — | — | "Appearance" (`dark_group`), "Behavior" |
| `Adwaita::SwitchRow` (`dark`) | 1 | — | `notify::active` → force dark / prefer light | "Dark Mode"; its whole group is hidden when the system supports colour schemes — **conditional** |
| `Adwaita::SwitchRow` (`autostart`) | 1 | — | `notify::active` → XDG background portal request | "Autostart in Background" |
| `Adwaita::SwitchRow` (`start_paused`) | 1 | — | bound to `start-paused` | "Always Start on Pause" |
| `Adwaita::SwitchRow` (`inhibition`) | 1 | — | bound to `inhibit-suspension` | "Inhibit suspension while playing" |
| `Adwaita::AlertDialog` | 1 | — | response `ok` | **error state**: "Authorization failed" / "Make sure Blanket has permission to run in the background…" when the portal denies autostart; the switch reverts |
| `Adwaita::Toast` | 1 | — | — | **error state**: "The autostart request failed." |

Port note: upstream uses `Xdp.Portal.request_background`. There is no `Xdp`
typelib in this fork's dev shell — see Blockers.

## lib/blanket/shortcuts_dialog.rb — Keyboard Shortcuts

Upstream: `data/resources/shortcuts.blp` — a standalone named root with no
backing Python file. **Present** (51 lines), with the six items.

`Adwaita::ShortcutsDialog` with one `Adwaita::ShortcutsSection` "General" and
six `Adwaita::ShortcutsItem`s: `app.playpause` "Play/Pause Sounds", `app.open`
"Add Custom Sound", `win.close` "Close Window", `app.preferences`
"Preferences", `app.shortcuts` "Keyboard Shortcuts", `app.quit` "Quit".
Upstream addresses each item by action name and lets libadwaita look the
accelerator up; the port carries the accelerator literally, because that is the
form the Ruby bindings take positionally. Three of the six actions do not exist
in the port yet, so those rows document accelerators nothing answers.

**Upstream bug, deliberately not reproduced:** `primary-menu` and this dialog
both reference `app.shortcuts`, which `blanket/main.py` never installs, so the
menu item is insensitive upstream. The port installs the action.

## lib/blanket/about_dialog.rb — About Blanket

Upstream: `data/resources/about.blp` (named root `about`) + `on_about` in
`blanket/main.py` + the credit tables in `blanket/define.in`. **Present** (43 lines).

`Adwaita::AboutDialog`: application name "Blanket", comments "Listen to
different sounds", copyright, developer "Rafael Mardojai CM", website
`apps.gnome.org/Blanket`, issue URL, GPL-3.0, translator credits, version, app
icon, developers, designers (`ARTISTS`), a "Source Code" link, and two credit
sections — "Sounds by" (`SOUND_ARTISTS`, 14 entries) and "Sounds edited by"
(`SOUND_EDITORS`).

---

## Non-widget units the UI cannot work without

Every component above binds to one of these.

| Upstream | Target | Present | What it is |
|---|---|---|---|
| `blanket/define.in` | `lib/blanket/define.rb` | **yes** (107 lines) | APP_ID, RES_PATH, data/icon/sound/schema paths, the sound catalogue (3 groups / 12 sounds), 2 noises, credits tables. The Meson templating is gone — values are literals, the version comes from the gem, and assets are files rather than a GResource bundle |
| `blanket/settings.py` | `lib/blanket/settings.rb` | **yes** (318 lines) | `Gio::Settings` wrapper, per-preset `Gio::Settings` in delay-apply mode, custom-audio and preset helpers, legacy volume migration, `preset-changed` as a block list rather than a GObject signal |
| `blanket/preset.py` | `lib/blanket/preset.rb` | **yes** (61 lines) | name/active, read through `Settings`, with `#on_changed` blocks in place of property bindings |
| `blanket/sound.py` | `lib/blanket/sound.rb` | **yes** (252 lines) | one sound: `playing`, `title`, `icon_name`, `error_message`, `failed`, `saved_volume`/`saved_mute`, lazy GStreamer branch attach/detach with a 5s delay |
| `blanket/main_player.py` | `lib/blanket/main_player.rb` | **yes** (405 lines) | singleton player **and** the app's list of sounds; one shared pipeline (audiomixer → convert → resample → volume → autoaudiosink), branch attach/detach with pad offsets, cubic/linear volume conversion, error recovery, suspend inhibition, preset next/prev. Not yet consumed by a window — see blocker 3 |
| `blanket/audio/bins.py` | `lib/blanket/audio/bins.rb` | **yes** (241 lines) | `SoundBin` base, `LoopBin` (uridecodebin + segment-seek looping with retries), `NoiseBin` (audiotestsrc) |
| `blanket/utils.py` | `lib/blanket/dummy_item_model.rb` | no | `Gio::ListModel` that appends one dummy item — the "Add…" tile |
| `blanket/mpris.py` | `lib/blanket/mpris.rb` | no | D-Bus `org.mpris.MediaPlayer2.Blanket`: Raise/Quit/Next/Previous/PlayPause/Play/Pause/Stop, Metadata, Volume, CanGoNext/Previous, PropertiesChanged |
| `data/com.rafaelmardojai.Blanket.gschema.xml.in` | `data/schemas/org.rubygtkproject.Blanket.gschema.xml` | **yes** | both schemas, same 13 + 4 key names, compiled to `data/schemas/gschemas.compiled`; the dev shell exports `GSETTINGS_SCHEMA_DIR` |
| `data/resources/style.css` | `lib/blanket/style.css` | **yes** | all 17 rules, loaded by `application.rb`'s `Gtk::CssProvider`. Most of them style widgets that do not exist yet |
| `data/resources/blanket.gresource.xml` | files on disk | **yes** for assets | 16 symbolic icons under `data/icons/hicolor/scalable/emblems`, 14 `.ogg` sounds under `data/sounds`, plus the app icon. The 12 `.ui` files have no counterpart by design |
| `po/` (57 locales, 87 msgids) | translation strategy | no | no gettext in the port; every label above is a literal English string |

---

## Summary of parity

Present on `ruby`: 5 of 14 UI units in full (preset chooser, preset row, preset
dialog, shortcuts dialog, about dialog), 1 partially (the application object,
with a placeholder window), and 7 of the 12 non-widget units (define, settings,
preset, sound, main_player, audio/bins, the stylesheet) plus the schemas and
every asset.

Missing: the window proper and everything that shows a sound on screen — the
sound grid and its tiles, the bottom bar, the volume popover and its rows, the
play/pause button, the sound context menu, the rename dialog, preferences, and
MPRIS. The GStreamer player stack itself (`sound.rb`, `main_player.rb`,
`audio/bins.rb`) is ported but unreachable from the UI, because nothing yet
calls `MainPlayer.get`'s model from a window.

## Blockers and open questions

1. ~~No GStreamer in the dev shell.~~ **Resolved.** `flake.nix` now has a
   `gstStack` (`gstreamer`, `gst-plugins-base`, `gst-plugins-good`) feeding
   both `buildInputs` and `typelibPath`, a `gstPluginPath` exported as
   `GST_PLUGIN_SYSTEM_PATH_1_0`, and a `rubyGstGem` override building the
   `gstreamer` gem's C extension against `libunwind`/`elfutils`/`orc`.
   `sound.rb`, `bins.rb` and `main_player.rb` are written and use it.
2. **No `Xdp`/ASHPD binding wired.** `preferences.py` requests autostart
   through `Xdp.Portal` + `XdpGtk4` (libportal). This fork's mandatory-gems
   list names `ashpd` (the `Ashpd` Rust gem, portal bindings) for exactly this
   kind of call, and it is **not yet in the gemspec, `nix/Gemfile` or
   `flake.nix`'s `gtkStack`** — the gemspec in fact has no runtime
   dependencies declared at all (not even `gtk4`/`adwaita`/`glib2`, though
   `nix/Gemfile` separately lists `adwaita`, `gtk4`, `gstreamer`). This has to
   be wired in — gemspec, `nix/Gemfile`, regenerated lock, flake typelib —
   before `preferences_dialog.rb` is written, per the fork's house rules; the
   autostart switch, its "Authorization failed" dialog and its failure toast
   depend on it.
3. **How the window's `bind_model` reaches `MainPlayer`.** Upstream's
   `MainPlayer` and `DummyItemModel` both implement `Gio.ListModel` in Python
   via `do_get_item`. The ported `main_player.rb` comments that it "also
   implements `Gio.ListModel`, which the window ... [uses]" but does not
   itself declare the interface (grep finds no `ListModel`/`ListStore`/
   `do_get_item` in the file) — so whether the window binds to it directly,
   through a `Gio::ListStore` kept in sync, or some other shape is still
   undecided, and decides how `window.rb`, `sound_item.rb`'s grid and
   `dummy_item_model.rb` get built.
4. **`Adwaita::ApplicationWindow`** is flagged broken in the `ruby-gtk` skill's
   quirks reference, and `application.rb` uses it. It has not been driven
   headlessly yet, so this is still open.
5. **No translations.** 57 locales and 87 msgids upstream; the port has no
   gettext and no catalogue. Needs a decision before more literal strings are
   written.
6. **Resolved since the first survey:** both GSettings schemas exist and
   compile, the dev shell exports `GSETTINGS_SCHEMA_DIR`, the stylesheet is
   ported whole, and all 16 icons and 14 sounds are on disk with an icon-theme
   search path. The `lib/blanket/*.rb` path convention (rather than the pilot's
   flat `lib/*.rb`) is settled, forced by the gem layout.
