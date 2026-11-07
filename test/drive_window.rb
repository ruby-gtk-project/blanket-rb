# frozen_string_literal: true

# Drives the main window: the sounds grid, the volume popover, a sound's
# context menu, the rename dialog and the preferences dialog.
#
# The settings live in the memory GSettings backend, so a run neither reads
# nor writes the real configuration. Only a noise sound (audiotestsrc, no
# dynamic pads) is ever told to play — a looped file goes through
# uridecodebin's "pad-added" signal, which upstream's audio/bins.rb fires
# from a GStreamer streaming thread, and invoking a Ruby block from a thread
# Ruby never registered is a pre-existing crash this driver works around
# rather than exercises.

ENV["GSETTINGS_BACKEND"] = "memory"

require "tmpdir"
ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "blanket"
require "blanket/preferences_dialog"
require "blanket/sound_context_menu"
require "blanket/sound_rename_dialog"
require_relative "gtk_driver"

def window(app) = app.send(:blanket_window)

# FlowBox and ListBox carry no item count in these bindings; both are plain
# Gtk::Widget containers, so counting means walking the generic widget tree.
def children_count(widget)
  count = 0
  child = widget.first_child

  while child
    count += 1
    child = child.next_sibling
  end

  count
end

GtkDriver.drive(Blanket::Application.new, shots: "tmp/shots", interval: 900) do |d, app|
  d.window { window(app).window }

  d.step("the window builds") do
    @sounds_count = Blanket::Define::SOUNDS.sum { |group| group[:sounds].length } + Blanket::Define::NOISES.length

    d.check("every sound plus the Add tile is in the grid") do
      children_count(window(app).send(:grid)) == (@sounds_count + 1)
    end
    d.check("the labels size group has every tile's label") { window(app).send(:labels_group).widgets.length == @sounds_count + 1 }
    # #get_property, not #visible? — the volume popover is never popped up
    # in this driver, so its never-mapped children read as not-effectively-
    # visible regardless of the "visible" property this exercises.
    d.check("the volume popover's extra box starts hidden") { !window(app).send(:volume_box).get_property("visible") }
    d.shot("01-window")
  end

  d.step("turning on a noise sound") do
    @noise = Blanket::MainPlayer.get.get_by_name("pink-noise")
    @tile = window(app).send(:tile_for, @noise)

    d.check("found the pink-noise tile") { !@tile.nil? }

    @noise.playing = true
  end

  d.step("the tile and the volume list follow") do
    d.check("the tile's scale is now visible") { @tile.send(:scale).visible? }
    d.check("the tile's icon is accented") { @tile.send(:icon).css_classes.include?("accent") }
    d.check("the volume popover's extra box is visible now") { window(app).send(:volume_box).get_property("visible") }
    d.check("one row in the volume list") { children_count(window(app).send(:volume_list)) == 1 }
    d.shot("02-sound-playing")
  end

  d.step("a built-in sound's context menu carries no custom section") do
    index = Blanket::MainPlayer.get.get_index("pink-noise")
    menu = Blanket::SoundContextMenu.new(@noise, index)

    d.check("one section only") { menu.menu_model.n_items == 1 }
  end

  d.step("adding a custom sound") do
    @custom = Blanket::Sound.new("waterfall", uri: "file:///tmp/waterfall.ogg", custom: true, failed: true)
    Blanket::MainPlayer.get.append(@custom)

    d.check("the grid grew by one") { children_count(window(app).send(:grid)) == (@sounds_count + 2) }
  end

  d.step("a custom sound's context menu carries Rename and Remove") do
    index = Blanket::MainPlayer.get.get_index("waterfall")
    @menu = Blanket::SoundContextMenu.new(@custom, index)

    d.check("two sections") { @menu.menu_model.n_items == 2 }
  end

  d.step("the rename dialog opens for it") do
    @dialog = Blanket::SoundRenameDialog.new(@custom, 0)
    @dialog.present(window(app).window)
  end

  d.step("it is prefilled and starts insensitive") do
    d.check("the subtitle is the sound's name") { @dialog.title_widget.subtitle == "waterfall" }
    d.check("the entry carries the current name") { @dialog.name_row.text == "waterfall" }
    d.check("Save starts insensitive (same name)") { !@dialog.accept_button.sensitive? }
    d.shot("03-rename-dialog")
  end

  d.step("typing a free name enables Save") do
    @dialog.name_row.text = "cascade"

    d.check("Save is sensitive") { @dialog.accept_button.sensitive? }
  end

  d.step("saving renames the sound") do
    @dialog.accept_button.signal_emit("clicked")

    d.check("the sound's name followed") { @custom.name == "cascade" }
    d.check("the sound's title followed") { @custom.title == "cascade" }
  end

  d.step("the preferences dialog opens") do
    @prefs = Blanket::PreferencesDialog.new(window(app).window)
    @prefs.present(window(app).window)
  end

  d.step("it reflects the current settings") do
    settings = Blanket::Settings.get

    d.check("start-paused switch matches settings") { @prefs.start_paused_row.active? == settings.start_paused }
    d.check("inhibition switch matches settings") { @prefs.inhibition_row.active? == settings.inhibit_suspension }
    d.check("dark-mode switch matches settings") { @prefs.dark_row.active? == settings.dark_mode }
    d.check("autostart row starts off") { !@prefs.autostart_row.active? }
    d.shot("04-preferences")
  end

  d.step("toggling dark mode writes the setting and the style manager") do
    @prefs.dark_row.active = !@prefs.dark_row.active?
  end

  d.step("the dark-mode setting and style scheme followed") do
    settings = Blanket::Settings.get

    d.check("dark-mode flipped") { settings.dark_mode == @prefs.dark_row.active? }
    d.check("the style scheme followed") do
      expected = @prefs.dark_row.active? ? :force_dark : :prefer_light
      Adwaita::StyleManager.default.color_scheme == expected
    end
  end

  d.step("toggling inhibition writes the setting") do
    @prefs.inhibition_row.active = !@prefs.inhibition_row.active?
  end

  d.step("the setting followed") do
    d.check("inhibit-suspension flipped") { Blanket::Settings.get.inhibit_suspension == @prefs.inhibition_row.active? }
  end

  # The one feature a removed `ashpd` dependency might have served: upstream
  # gates this switch behind the XDG Background portal
  # (`Xdp.Portal#request_background`), but this port has no binding for that
  # portal (ashpd's gem binds Account/Camera/OpenUri/Screenshot/Settings/Trash,
  # not Background -- see preferences_dialog.rb), so the switch here writes
  # the "autostart" GSetting directly via the same Gio::Settings#bind every
  # other switch on this dialog uses. Exercise that bound path end to end
  # rather than only checking its resting state.
  d.step("toggling autostart writes the setting directly (no portal)") do
    @prefs.autostart_row.active = !@prefs.autostart_row.active?
  end

  d.step("the autostart setting followed") do
    d.check("autostart flipped") { Blanket::Settings.get.autostart == @prefs.autostart_row.active? }
  end

  # The action lives on the window itself, unprefixed; toggling a stateful
  # action's state from code is #change_action_state, not #activate_action
  # (which takes the *activate* parameter — null for this action, since it
  # is toggled, not given a value — and would otherwise raise a parameter
  # mismatch the console shows as a GLib-GIO-CRITICAL).
  d.step("hiding inactive sounds filters the grid") do
    window(app).window.change_action_state("hide-inactive", GLib::Variant.new(true))
  end

  d.step("only the playing sound and the Add tile remain") do
    d.check("two tiles left") { children_count(window(app).send(:grid)) == 2 }
    d.shot("05-hide-inactive")

    window(app).window.change_action_state("hide-inactive", GLib::Variant.new(false))
  end

  d.step("showing inactive sounds again restores the grid") do
    d.check("every sound is back") { children_count(window(app).send(:grid)) == (@sounds_count + 2) }
  end
end
