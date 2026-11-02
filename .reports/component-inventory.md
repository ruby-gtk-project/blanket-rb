# blanket — upstream component inventory

Survey of `origin/master` (Blanket, Python + PyGObject + GTK4/libadwaita +
GStreamer) against `lib/` on the `ruby` branch, for the full-parity Ruby port.

Method: the `component-identification` skill. Upstream carries blueprint UI, so
the eleven `data/resources/*.blp` files were read first — they are the real
widget trees, the CSS classes and the signals — then every Python module that
backs one, plus the GSettings schema, the GResource manifest and `po/`.

## Totals

| | Upstream | `ruby` branch |
|---|---|---|
| UI units (blueprint template / named root / app class) | 13 | 1 (placeholder) |
| Blueprint files | 11 | 0 (by design — widgets are memoized methods) |
| Python modules | 20 | 3 Ruby files, 1 of them a stub window |
| Distinct widget types | ~30 | 5 |
| CSS classes applied | 10 (`accent`, `circular`, `devel`, `error`, `flat`, `menu`, `playpause`, `preset-row`, `selected`, `sound-item`, `sound-view`, `suggested-action`, `volume-row`, `volume-separator`, `caption-heading`) | 0 |
| Stylesheet | `data/resources/style.css`, 11 rules | none |
| GActions | 14 (`app.*` ×12, `win.*` ×2) | 0 |
| Accelerators | 6 | 0 |
| GSettings schemas | 2 (app + `.preset`), 13 + 4 keys | none |
| Translated strings | 87 msgids, 60 locales | none |

The `ruby` branch is at the scaffold stage: `lib/blanket/application.rb` is a
`Gtk::Application` with an `Adwaita::ToolbarView`, an empty `Adwaita::HeaderBar`
and an `Adwaita::StatusPage` reading "The Ruby port has not been written yet."
Nothing else of the app exists.

## Path convention

The pilot port (`gnome-contacts-rb`) is flat `lib/<thing>.rb`. This fork is
packaged as the `blanket-rb` gem and already has `lib/blanket.rb` +
`lib/blanket/application.rb`, with `exe/blanket` doing `require "blanket"`.
Targets below therefore keep this fork's existing namespace,
`lib/blanket/<thing>.rb`, one upstream unit per file.

---

## lib/blanket/application.rb — the application object: actions, accelerators, MPRIS, power monitor

Upstream: `blanket/main.py`. **Exists as a placeholder only** — none of the
below is present.

| Thing | × | Notes |
|---|---:|---|
| `Gtk::Application` (upstream `Adw.Application`) | 1 | `HANDLES_COMMAND_LINE`; `resource_base_path`; sets `PULSE_PROP_application.icon_name` |
| `--hidden` command-line option | 1 | starts the window hidden; `do_command_line` |
| `Gio::PowerProfileMonitor` | 1 | `notify::power-saver-enabled` → pause playback + show power toast |
| `Adwaita::StyleManager` | 1 | forces dark when the system has no colour schemes |
| Signal `shutdown` | 1 | saves settings, stops the player |
| Signal `close-request` on the window | 1 | hide when background playback is on, else save window state and quit |

Actions installed (names are literals; the `space` accelerator is removed while
a text-entry dialog is open and restored on close — `set_space_accel` /
`unset_space_accel`):

| Action | Kind | Accelerator |
|---|---|---|
| `app.quit` | simple | `<Ctl>q` |
| `app.about` | simple | — |
| `app.preferences` | simple | `<Ctl>comma` |
| `app.background-playback` | stateful (boolean) | — |
| `app.playpause` | simple | `<Ctl>m`, `space` |
| `app.play` | simple | — |
| `app.add-preset` | simple | — |
| `app.reset-volumes` | simple | — |
| `app.open` | simple | `<Ctl>o` |
| `app.remove-sound` | simple, param `u` | — |
| `app.rename-sound` | simple, param `u` | — |
| `win.close` | simple | `<Ctl>w` |
| `win.hide-inactive` | stateful (boolean) | `<Ctl>h` |

## lib/blanket/window.rb — the main window: sound grid, bottom bar, menus

Upstream: `blanket/window.py` + `data/resources/window.blp`. **Missing.**

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

Upstream: `blanket/widgets/preset_chooser.py` + `data/resources/preset-chooser.blp`. **Missing.**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk::MenuButton` | 1 | — | `notify::selected` | `always-show-arrow`; tooltip "Presets Menu" |
| `Gtk::Label` | 1 | — | — | bound to the selected preset's name, ellipsized |
| `Gtk::Popover` | 1 | `menu` | — | width 250, max content 300×400 |
| `Gtk::ScrolledWindow` | 1 | — | — | propagates natural size |
| `Gtk::ListBox` (`presets_list`) | 1 | — | `row-activated` | `bind_model` over a `Gio::ListStore` of `Preset` |

Repeater: one `PresetRow` per preset. Also listens to `Settings` `preset-changed`.

## lib/blanket/preset_row.rb — one preset in the preset popover

Upstream: `blanket/widgets/preset_row.py` + `data/resources/preset-row.blp`. **Missing.**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk::ListBoxRow` | 1 | `preset-row`, `selected` (dynamic, added on `notify::selected`) | `notify::selected` | `.preset-row.selected label` is bold |
| `Gtk::Box` | 3 | — | — | row body, button group |
| `Gtk::Label` (`name`) | 1 | — | — | bound to `Preset#name`, max 16 chars |
| `Gtk::Image` | 1 | — | — | `object-select-symbolic`, visible when selected |
| `Gtk::Button` (`rename_btn`) | 1 | `flat`, `circular` | `clicked` → popdown + `PresetDialog(preset)` | `document-edit-symbolic`, tooltip "Rename Preset"; visible only for custom presets |
| `Gtk::Button` (`delete_btn`) | 1 | `flat`, `circular` | `clicked` → remove preset, reselect default | `edit-delete-symbolic`, tooltip "Delete Preset"; custom presets only |

## lib/blanket/preset_dialog.rb — "New Preset" / "Edit Preset"

Upstream: `blanket/widgets/preset_dialog.py` + `data/resources/preset-dialog.blp`. **Missing.**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adwaita::Dialog` | 1 | — | `realize` → unset space accel; `closed` → restore it | 360×148; focus widget is the entry |
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

Upstream: `blanket/preferences.py` + `data/resources/preferences.blp`. **Missing.**

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
typelib binding in this fork's dev shell — see Blockers.

## lib/blanket/shortcuts_dialog.rb — Keyboard Shortcuts

Upstream: `data/resources/shortcuts.blp` — a standalone named root with no
backing Python file. **Missing.**

`Adwaita::ShortcutsDialog` with one `Adwaita::ShortcutsSection` "General" and
six `Adwaita::ShortcutsItem`s, each addressed by action name: `app.playpause`
"Play/Pause Sounds", `app.open` "Add Custom Sound", `win.close` "Close Window",
`app.preferences` "Preferences", `app.shortcuts` "Keyboard Shortcuts",
`app.quit` "Quit".

**Upstream bug to reproduce or fix deliberately:** `primary-menu` and this
dialog both reference `app.shortcuts`, but `blanket/main.py` never installs that
action. The menu item is therefore insensitive upstream.

## lib/blanket/about_dialog.rb — About Blanket

Upstream: `data/resources/about.blp` (named root `about`) + `on_about` in
`blanket/main.py` + the credit tables in `blanket/define.in`. **Missing.**

`Adwaita::AboutDialog`: application name "Blanket", comments "Listen to
different sounds", copyright, developer "Rafael Mardojai CM", website
`apps.gnome.org/Blanket`, issue URL, GPL-3.0, translator credits. Filled in
code with version, app icon, developers, designers (`ARTISTS`), a "Source Code"
link, and two credit sections — "Sounds by" (`SOUND_ARTISTS`, 14 entries) and
"Sounds edited by" (`SOUND_EDITORS`).

---

## Non-widget units the UI cannot work without

All **missing**. Listed because every component above binds to one of them.

| Upstream | Target | What it is |
|---|---|---|
| `blanket/define.in` | `lib/blanket/define.rb` | APP_ID, RES_PATH, the sound catalogue (3 groups / 12 sounds), 2 noises, credits tables |
| `blanket/settings.py` | `lib/blanket/settings.rb` | `Gio::Settings` singleton, per-preset `Gio::Settings` in delay-apply mode, custom-audio and preset helpers, legacy volume migration, `preset-changed` signal |
| `blanket/preset.py` | `lib/blanket/preset.rb` | `GObject` with `name`/`active`, bound to the preset schema |
| `blanket/sound.py` | `lib/blanket/sound.rb` | one sound: `playing`, `title`, `icon_name`, `error_message`, `failed`, `saved_volume`/`saved_mute`, lazy GStreamer branch attach/detach with a 5s delay |
| `blanket/main_player.py` | `lib/blanket/main_player.rb` | singleton player **and** the app's `Gio::ListModel`; one shared pipeline (audiomixer → convert → resample → volume → autoaudiosink), branch attach/detach with pad offsets, cubic/linear volume conversion, error recovery, suspend inhibition, preset next/prev |
| `blanket/audio/bins.py` | `lib/blanket/audio/bins.rb` | `SoundBin` base, `LoopBin` (uridecodebin + segment-seek looping with retries), `NoiseBin` (audiotestsrc) |
| `blanket/utils.py` | `lib/blanket/dummy_item_model.rb` | `Gio::ListModel` that appends one dummy item — the "Add…" tile |
| `blanket/mpris.py` | `lib/blanket/mpris.rb` | D-Bus `org.mpris.MediaPlayer2.Blanket`: Raise/Quit/Next/Previous/PlayPause/Play/Pause/Stop, Metadata, Volume, CanGoNext/Previous, PropertiesChanged |
| `data/com.rafaelmardojai.Blanket.gschema.xml.in` | GSettings schema in-tree + compiled for the dev shell | app schema (13 keys: `window-state`, `autostart`, `start-paused`, `dark-mode`, `inhibit-suspension`, `scroll-position`, `volume`, `playing`, `background-playback`, `custom-audios`, `presets`, `active-preset`, deprecated `sounds-volume`) and `.preset` schema (`visible-name`, `sounds-volume`, `sounds-mute`, `hide-inactive`) |
| `data/resources/style.css` | `lib/blanket/style.css` loaded via `Gtk::CssProvider` from `application.rb` | 11 rules: `.preset-row`, `.preset-row.selected label`, `.volume-separator`, `.volume-row` (+ `:hover`, `label`, `scale`), `button.playpause`, `.sound-view`, `.sound-item` (+ `:hover`, `image`, `image.accent`, scale trough/slider/highlight) |
| `data/resources/blanket.gresource.xml` | asset loading | 11 UI files (not needed — the port builds widgets in code), `style.css`, 16 symbolic icons, 14 `.ogg` sounds. **The icons and sounds must be carried over**; the port has neither |
| `po/` (60 locales, 87 msgids) | translation strategy | no gettext in the port yet; every label above is currently untranslated |

---

## Summary of parity

Present on `ruby`: 1 of 13 UI units, and that one only as a placeholder shell
(`lib/blanket/application.rb` — no actions, no accelerators, no menus, no real
content). Everything else in this document is to be written.

## Blockers and open questions

1. **No GStreamer in the dev shell (unverified).** The whole app is a GStreamer
   mixer. `flake.nix` must provide `gstreamer`, `gst-plugins-base`,
   `gst-plugins-good` and their typelibs, and the Ruby side needs working
   `Gst`/`GstAudio` introspection. Confirm before porting `main_player.rb`.
2. **No `Xdp` (libportal) binding.** `preferences.py` requests autostart through
   `Xdp.Portal` + `XdpGtk4`. If the typelib is absent the autostart switch, its
   "Authorization failed" dialog and its failure toast cannot be ported as-is.
3. **GSettings schemas must exist at runtime.** Nothing works until the two
   schemas are compiled into a `GSETTINGS_SCHEMA_DIR` the dev shell exports;
   the dynamic per-preset `Gio::Settings.new_with_path` + `delay`/`apply`
   pattern needs checking against the Ruby bindings.
4. **`Adwaita::ApplicationWindow` is flagged broken** in the `ruby-gtk` skill's
   quirks reference, yet the existing `lib/blanket/application.rb` uses it. The
   window unit must be driven headlessly early to find out which it is.
5. **Custom `Gio::ListModel` implementations.** `MainPlayer` and
   `DummyItemModel` both implement `Gio::ListModel` in Python via `do_get_item`.
   Whether Ruby GTK allows implementing a GInterface this way is unknown; a
   `Gio::ListStore` + a separate player object may be the port's shape instead.
6. **Path convention deviates from the pilot.** The pilot is flat `lib/*.rb`;
   this fork's gem layout forces `lib/blanket/*.rb`. Confirmed against
   `exe/blanket` and the gemspec, but worth an explicit decision.
7. **Assets.** 16 symbolic SVG icons and 14 `.ogg` sounds live in upstream's
   GResource. The port needs them on disk (or in its own resource bundle) plus
   an icon-theme search path, or every sound tile renders a missing icon.
8. **`app.shortcuts` is referenced but never installed upstream** (see the
   shortcuts unit). Decide whether the port reproduces the dead menu item or
   installs the action.
