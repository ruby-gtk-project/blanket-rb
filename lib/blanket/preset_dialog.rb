# frozen_string_literal: true

require "adwaita"
require_relative "i18n"
require_relative "preset"
require_relative "settings"

module Blanket
  # Ported from blanket/widgets/preset_dialog.py and
  # data/resources/preset-dialog.blp.
  #
  # One dialog serving both jobs upstream gives it: with no preset it creates
  # one from the active preset's volumes ("New Preset"), with a preset it
  # renames that one ("Edit Preset"). The Save button stays insensitive until
  # the entry holds a name that is neither empty nor the name the preset
  # already has.
  class PresetDialog
    include GetText

    # `on_created` is called with the new Preset, so the chooser that opened
    # the dialog can add a row for it and select it.
    def initialize(preset: nil, on_created: nil)
      @preset = preset
      @on_created = on_created
    end

    def build
      dialog.tap do |dlg|
        dlg.child = toolbar_view

        toolbar_view.tap do |view|
          view.add_top_bar(header_bar)
          view.content = page

          header_bar.tap do |bar|
            bar.title_widget = title_widget
            bar.pack_start(cancel_button)
            bar.pack_end(accept_button)

            cancel_button.signal_connect("clicked") { dlg.close }
            accept_button.signal_connect("clicked") { accept }
          end

          page.tap do |prefs|
            prefs.add(group)

            group.tap do |grp|
              grp.add(name_row)

              name_row.signal_connect("changed") { update_sensitivity }
            end
          end
        end
      end
    end

    def present(parent) = build.present(parent)

    def dialog
      @dialog ||= Adwaita::Dialog.new.tap do |dlg|
        dlg.title = dialog_title
        dlg.width_request = 360
        dlg.height_request = 148
        dlg.focus_widget = name_row
      end
    end

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

    def header_bar
      @header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
        bar.show_end_title_buttons = false
        bar.show_start_title_buttons = false
      end
    end

    def title_widget
      @title_widget ||= Adwaita::WindowTitle.new(dialog_title, subtitle)
    end

    def cancel_button = @cancel_button ||= Gtk::Button.new(label: _("Cancel"))

    def accept_button
      @accept_button ||= Gtk::Button.new(label: _("Save")).tap do |button|
        button.sensitive = false
        button.add_css_class("suggested-action")
      end
    end

    def page = @page ||= Adwaita::PreferencesPage.new
    def group = @group ||= Adwaita::PreferencesGroup.new

    def name_row
      @name_row ||= Adwaita::EntryRow.new.tap do |row|
        row.title = _("Preset Name")
        row.selectable = false
        row.text = initial_name
      end
    end

    private

      def editing? = !@preset.nil?

      # Conditionals are kept out of the assignments above: the house style
      # bans `x = cond ? a : b`.
      def dialog_title
        if editing?
          _("Edit Preset")
        else
          _("New Preset")
        end
      end

      def subtitle
        if editing?
          @preset.name
        else
          ""
        end
      end

      def initial_name
        if editing?
          @preset.name
        else
          ""
        end
      end

      def entered_name = name_row.text.strip

      # Mirrors upstream's _on_entry_changed: an empty name, or the name the
      # preset already carries, is not something to save.
      def update_sensitivity
        entered_name.then do |name|
          if editing?
            accept_button.sensitive = !name.empty? && name != @preset.name
          else
            accept_button.sensitive = !name.empty?
          end
        end
      end

      def accept
        entered_name.then do |name|
          unless name.empty?
            if editing?
              @preset.name = name
            else
              create(name)
            end
            dialog.close
          end
        end
      end

      def create(name)
        Preset.new(Settings.get.add_preset(name)).tap do |preset|
          name_row.text = ""
          @on_created&.call(preset)
        end
      end
  end
end
