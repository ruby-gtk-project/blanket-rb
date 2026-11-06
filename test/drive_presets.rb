# frozen_string_literal: true

# Drives the preset chooser, the preset dialog and the two application dialogs
# the primary menu opens.
#
# The settings live in the memory GSettings backend, so a run neither reads nor
# writes the real configuration.

ENV["GSETTINGS_BACKEND"] = "memory"

require "tmpdir"
ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "blanket"
require "blanket/about_dialog"
require "blanket/preset_dialog"
require "blanket/shortcuts_dialog"
require_relative "gtk_driver"

settings = nil

# `window` and `presets_chooser` used to be the application's own methods,
# from before window.py's content had a Window class of its own; now both
# live there, reached the way a step reaches any other private collaborator.
def window(app) = app.send(:blanket_window)

def presets_chooser(app) = window(app).send(:presets_chooser)

# The interval is generous so a dialog's open animation has finished before
# the next step photographs it.
GtkDriver.drive(Blanket::Application.new, shots: "tmp/shots", interval: 900) do |d, app|
  d.window { window(app).window }

  d.step("the window builds") do
    settings = Blanket::Settings.get

    d.check("the window carries the app's name") { window(app).window.title == "Blanket" }
    d.check("one preset to start with") { settings.presets.length == 1 }
    d.check("the default preset is named Default") { settings.active_preset_name == "Default" }
    d.check("the chooser is hidden with a single preset") { !presets_chooser(app).menu_button.visible? }
    d.check("the chooser's label is the active preset") { presets_chooser(app).label.label == "Default" }
    d.check("the stylesheet loaded") { app.css_provider.to_s.include?("preset-row") }
    d.shot("01-window")
  end

  d.step("the new-preset dialog opens") do
    @dialog = Blanket::PresetDialog.new(on_created: ->(preset) { preset.activate })
    @dialog.present(window(app).window)
  end

  d.step("the dialog refuses an empty name") do
    d.check("the dialog is showing") { !window(app).window.visible_dialog.nil? }
    d.check("Save starts insensitive") { !@dialog.accept_button.sensitive? }
    d.check("the title is New Preset") { @dialog.dialog.title == "New Preset" }
    d.shot("02-new-preset")
  end

  d.step("typing a name makes Save sensitive") do
    @dialog.name_row.text = "Evening"

    d.check("Save is sensitive") { @dialog.accept_button.sensitive? }
  end

  d.step("saving creates the preset and selects it") do
    @dialog.accept_button.signal_emit("clicked")
  end

  d.step("the chooser shows both presets") do
    d.check("two presets") { settings.presets.length == 2 }
    d.check("the new one is active") { settings.active_preset_name == "Evening" }
    d.check("the chooser is visible now") { presets_chooser(app).menu_button.visible? }
    d.check("the chooser's label followed") { presets_chooser(app).label.label == "Evening" }
    d.check("two rows") { presets_chooser(app).rows.length == 2 }
    d.check("the new row is marked selected") { presets_chooser(app).rows[1].row.css_classes.include?("selected") }
    d.check("the default row is not") { !presets_chooser(app).rows[0].row.css_classes.include?("selected") }
    d.check("the new row's label") { presets_chooser(app).rows[1].name_label.label == "Evening" }
  end

  # Gtk::Widget#visible? is the effective visibility, so the rows' buttons read
  # as hidden until the popover they live in is actually up.
  d.step("the popover opens") do
    presets_chooser(app).menu_button.popup
  end

  d.step("the rows carry the right buttons") do
    d.check("the default row cannot be renamed") { !presets_chooser(app).rows[0].rename_button.visible? }
    d.check("the default row cannot be deleted") { !presets_chooser(app).rows[0].delete_button.visible? }
    d.check("the new row can be renamed") { presets_chooser(app).rows[1].rename_button.visible? }
    d.check("the new row can be deleted") { presets_chooser(app).rows[1].delete_button.visible? }
    d.check("the active row shows the check mark") { presets_chooser(app).rows[1].check_image.visible? }
    d.shot("03-two-presets")
  end

  d.step("activating a row makes its preset active") do
    presets_chooser(app).presets_list.signal_emit("row-activated", presets_chooser(app).rows[0].row)
  end

  d.step("the default preset becomes active") do
    d.check("the default preset is active") { settings.active_preset_name == "Default" }
    d.check("the default row is marked selected") { presets_chooser(app).rows[0].row.css_classes.include?("selected") }

    presets_chooser(app).presets_list.signal_emit("row-activated", presets_chooser(app).rows[1].row)
  end

  d.step("and back to the new one") do
    d.check("the new preset is active again") { settings.active_preset_name == "Evening" }
  end

  d.step("the volumes of the active preset were copied") do
    settings.set_sound_volume("rain", 0.4)

    d.check("the volume is saved") { settings.get_sound_volume("rain") == 0.4 }
    d.check("and it is scoped to this preset") do
      settings.get_preset_volumes(settings.presets[0]).empty?
    end
  end

  d.step("renaming opens the edit dialog") do
    presets_chooser(app).rows[1].rename_button.signal_emit("clicked")
  end

  d.step("the edit dialog is prefilled") do
    d.check("a dialog is showing") { !window(app).window.visible_dialog.nil? }
    d.check("it is the edit dialog") { window(app).window.visible_dialog.title == "Edit Preset" }
    d.shot("04-edit-preset")
    window(app).window.visible_dialog.close
  end

  d.step("deleting the preset falls back to the default") do
    presets_chooser(app).rows[1].delete_button.signal_emit("clicked")
  end

  d.step("the chooser is back to one preset") do
    d.check("one preset") { settings.presets.length == 1 }
    d.check("the default preset is active") { settings.active_preset_name == "Default" }
    d.check("one row") { presets_chooser(app).rows.length == 1 }
    d.check("the chooser is hidden again") { !presets_chooser(app).menu_button.visible? }
  end

  d.step("the shortcuts dialog opens") do
    Blanket::ShortcutsDialog.new.present(window(app).window)
  end

  d.step("the shortcuts dialog renders") do
    d.check("a dialog is showing") { !window(app).window.visible_dialog.nil? }
    d.shot("05-shortcuts")
    window(app).window.visible_dialog.close
  end

  d.step("the about dialog opens") do
    Blanket::AboutDialog.new.present(window(app).window)
  end

  d.step("the about dialog renders") do
    d.check("a dialog is showing") { !window(app).window.visible_dialog.nil? }
    d.shot("06-about")
    window(app).window.visible_dialog.close
  end

  d.step("the window state round-trips") do
    settings.set_window_state(width: 640, height: 480, maximized: false)

    d.check("width comes back") { settings.window_state[:width] == 640 }
    d.check("height comes back") { settings.window_state[:height] == 480 }
    d.check("maximized comes back") { settings.window_state[:maximized] == false }
  end

  d.step("custom audios round-trip") do
    settings.add_custom_audio("waterfall", "file:///tmp/waterfall.ogg")
    settings.rename_custom_audio("waterfall", "cascade")

    d.check("the renamed entry is there") do
      settings.custom_audios == {"cascade" => "file:///tmp/waterfall.ogg"}
    end

    settings.remove_custom_audio("cascade")

    d.check("and it goes away again") { settings.custom_audios.empty? }
  end
end
