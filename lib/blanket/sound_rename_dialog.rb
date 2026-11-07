# frozen_string_literal: true

require "adwaita"
require_relative "i18n"
require_relative "settings"

module Blanket
  # Ported from blanket/widgets/sound_rename_dialog.py and
  # data/resources/sound-rename-dialog.blp.
  #
  # Renames a custom sound: the Save button stays insensitive until the
  # entry holds a name that is neither empty, the sound's own name, nor the
  # name of another custom sound already saved.
  #
  # Upstream also toggles the app's space-bar play/pause accelerator off
  # while the dialog is open, so typing a space in the entry does not also
  # toggle playback; `on_space_unset`/`on_space_reset` arrive as callbacks
  # here so this dialog never has to know about the application object.
  class SoundRenameDialog
    include GetText

    def initialize(sound, index, on_space_unset: nil, on_space_reset: nil)
      @sound = sound
      @index = index
      @on_space_unset = on_space_unset
      @on_space_reset = on_space_reset
    end

    def build
      dialog.tap do |dlg|
        dlg.child = toolbar_view
        dlg.signal_connect("realize") { @on_space_unset&.call }
        dlg.signal_connect("closed") { @on_space_reset&.call }

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
        dlg.title = _("Rename Sound")
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

    def title_widget = @title_widget ||= Adwaita::WindowTitle.new(_("Rename Sound"), @sound.name)

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
        row.title = _("Sound Name")
        row.selectable = false
        row.text = @sound.name
      end
    end

    private

      def entered_name = name_row.text.strip

      def update_sensitivity
        entered_name.then do |name|
          if name.empty? || name == @sound.name || Settings.get.custom_audios.key?(name)
            accept_button.sensitive = false
          else
            accept_button.sensitive = true
          end
        end
      end

      def accept
        entered_name.then do |name|
          if name == @sound.name
            dialog.close
          elsif !name.empty? && !Settings.get.custom_audios.key?(name)
            Settings.get.rename_custom_audio(@sound.name, name)
            @sound.name = name
            @sound.title = name
            dialog.close
          end
        end
      end
  end
end
