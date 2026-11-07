# frozen_string_literal: true

require "adwaita"
require_relative "i18n"
require_relative "preset"

module Blanket
  # Ported from blanket/widgets/preset_row.py and
  # data/resources/preset-row.blp.
  #
  # One row of the preset popover: the preset's name, a check mark when it is
  # the active one, and rename and delete buttons on the presets the user
  # created. The default preset has neither button, because it can be neither
  # renamed nor removed.
  #
  # Upstream reaches the chooser through the active window to rename or delete;
  # here both arrive as callbacks, so the row never has to know what opened it.
  class PresetRow
    include GetText

    attr_reader :preset

    def initialize(preset, on_rename:, on_delete:)
      @preset = preset
      @on_rename = on_rename
      @on_delete = on_delete
    end

    def build
      row.tap do |listboxrow|
        listboxrow.child = box

        box.tap do |container|
          container.append(name_label)
          container.append(check_image)
          container.append(buttons_box)

          buttons_box.tap do |buttons|
            buttons.append(rename_button)
            buttons.append(delete_button)

            rename_button.signal_connect("clicked") { @on_rename.call(preset) }
            delete_button.signal_connect("clicked") { @on_delete.call(preset) }
          end
        end

        refresh
      end
    end

    # Re-reads the preset: its name, whether it is the active one, and whether
    # it is the default preset. Upstream gets these from property bindings; the
    # chooser calls this on every row when any of them moves.
    def refresh
      name_label.label = preset.name
      check_image.visible = preset.active?
      rename_button.visible = preset.custom?
      delete_button.visible = preset.custom?

      if preset.active?
        row.add_css_class("selected")
      else
        row.remove_css_class("selected")
      end
    end

    def row = @row ||= Gtk::ListBoxRow.new.tap { |listboxrow| listboxrow.add_css_class("preset-row") }

    def box
      @box ||= Gtk::Box.new(:horizontal, 6).tap do |container|
        container.hexpand = true
        container.valign = :center
      end
    end

    def name_label
      @name_label ||= Gtk::Label.new.tap do |label|
        label.ellipsize = :end
        label.xalign = 0
        label.max_width_chars = 16
      end
    end

    def check_image
      @check_image ||= Gtk::Image.new.tap do |image|
        image.icon_name = "object-select-symbolic"
        image.halign = :start
      end
    end

    def buttons_box
      @buttons_box ||= Gtk::Box.new(:horizontal, 6).tap do |container|
        container.hexpand = true
        container.halign = :end
      end
    end

    def rename_button
      @rename_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "document-edit-symbolic"
        button.tooltip_text = _("Rename Preset")
        button.add_css_class("flat")
        button.add_css_class("circular")
      end
    end

    def delete_button
      @delete_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "edit-delete-symbolic"
        button.tooltip_text = _("Delete Preset")
        button.add_css_class("flat")
        button.add_css_class("circular")
      end
    end
  end
end
