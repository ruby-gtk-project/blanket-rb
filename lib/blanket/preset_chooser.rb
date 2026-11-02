# frozen_string_literal: true

require "adwaita"
require_relative "preset"
require_relative "preset_dialog"
require_relative "preset_row"
require_relative "settings"

module Blanket
  # Ported from blanket/widgets/preset_chooser.py and
  # data/resources/preset-chooser.blp.
  #
  # The header bar's menu button: its label is the active preset's name, and
  # its popover lists every preset with a rename and a delete button. Picking a
  # row makes that preset active.
  #
  # Upstream backs the list with a Gio.ListStore of Preset GObjects and
  # bind_model; the rows here are rebuilt from Settings whenever the preset
  # list changes, which is the same work without a GObject model. Preset
  # objects are cached by id so each one subscribes to the settings once,
  # however many times its row is rebuilt.
  class PresetChooser
    # The rows currently in the popover, in the order the presets are listed.
    attr_reader :rows

    # `parent_window` is what the rename dialog is presented on.
    def initialize(parent_window)
      @parent_window = parent_window
      @rows = []
      @presets = {}
    end

    def build
      menu_button.tap do |button|
        button.child = label
        button.popover = popover

        popover.tap do |pop|
          pop.child = scrolled

          scrolled.tap do |scroller|
            scroller.child = presets_list

            presets_list.signal_connect("row-activated") { |_list, row| activate(row) }
          end
        end

        Settings.get.on_changed("presets") { reload }
        Settings.get.on_changed("active-preset") { refresh }
        reload
      end
    end

    # Rebuilds a row for every preset in the settings. Called on first build
    # and whenever a preset is added or removed.
    def reload
      @rows.each { |row| presets_list.remove(row.row) }
      @rows = Settings.get.presets.map { |preset_id| PresetRow.new(preset_for(preset_id), **callbacks) }
      @rows.each { |row| presets_list.append(row.build) }
      refresh
    end

    # Upstream hides the chooser while there is only one preset, and shows the
    # active preset's name on it.
    def refresh
      label.label = Settings.get.active_preset_name
      menu_button.visible = Settings.get.presets.length > 1
      @rows.each(&:refresh)
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap { |button| button.always_show_arrow = true }
    end

    def label = @label ||= Gtk::Label.new.tap { |text| text.ellipsize = :end }

    def popover
      @popover ||= Gtk::Popover.new.tap do |pop|
        pop.width_request = 250
        pop.add_css_class("menu")
      end
    end

    def scrolled
      @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroller|
        scroller.propagate_natural_width = true
        scroller.propagate_natural_height = true
        scroller.max_content_width = 300
        scroller.max_content_height = 400
        scroller.width_request = 300
      end
    end

    def presets_list = @presets_list ||= Gtk::ListBox.new.tap { |list| list.selection_mode = :none }

    private

      def callbacks = {on_rename: method(:rename), on_delete: method(:delete)}

      # One Preset per id, so the row rebuilds do not pile up subscriptions on
      # the settings. A rename or a change of active preset reaches the whole
      # list through #refresh.
      def preset_for(preset_id)
        @presets[preset_id] ||= Preset.new(preset_id).tap { |preset| preset.on_changed { refresh } }
      end

      def activate(row)
        @rows.find { |candidate| candidate.row == row }.then do |found|
          if found
            found.preset.activate
          end
        end
      end

      def rename(preset)
        popover.popdown
        PresetDialog.new(preset: preset).present(@parent_window)
      end

      # Removing the preset rewrites the settings' preset list, and the
      # subscription in #build rebuilds the rows from it.
      def delete(preset)
        preset.active?.then do |was_active|
          preset.remove.then do |index|
            unless index.nil?
              @presets.delete(preset.id)

              if was_active
                preset_for(Settings.get.presets.first).activate
              end
            end
          end
        end
      end
  end
end
