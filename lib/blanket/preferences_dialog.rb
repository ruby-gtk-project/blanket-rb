# frozen_string_literal: true

require "adwaita"
require_relative "i18n"
require_relative "settings"

module Blanket
  # Ported from blanket/preferences.py and data/resources/preferences.blp.
  #
  # Four switches: dark mode (shown only when the system itself cannot
  # supply a color scheme), autostart in background, starting paused and
  # inhibiting suspension while playing.
  #
  # Upstream's autostart switch asks the XDG Background portal
  # (`Xdp.Portal#request_background`) for permission before writing the
  # setting, so a user who refuses the portal prompt keeps the switch off.
  # This app's binding gem for XDG portals is `ashpd`, and its native
  # extension defines only the Screenshot, OpenUri, Trash, Settings, Camera
  # and Account portals — no Background portal — so there is nothing to call
  # here. The switch instead writes the setting directly, the way
  # start-paused and inhibit-suspension already do; it grants no background
  # permission the portal would otherwise have to confirm.
  class PreferencesDialog
    include GetText

    def initialize(window)
      @window = window
    end

    def build
      dialog.tap do |dlg|
        dlg.add(page)

        page.tap do |pg|
          pg.add(dark_group)
          pg.add(behavior_group)

          dark_group.tap { |grp| grp.add(dark_row) }

          behavior_group.tap do |grp|
            grp.add(autostart_row)
            grp.add(start_paused_row)
            grp.add(inhibition_row)
          end
        end

        dark_row.signal_connect("notify::active") { on_dark_toggled }
        Settings.get.settings.bind(
          "autostart",
          autostart_row,
          "active",
          Gio::SettingsBindFlags::DEFAULT,
        )
      end
    end

    def present(parent) = build.present(parent)

    def dialog = @dialog ||= Adwaita::PreferencesDialog.new

    def page = @page ||= Adwaita::PreferencesPage.new

    def dark_group
      @dark_group ||= Adwaita::PreferencesGroup.new.tap do |grp|
        grp.title = _("Appearance")
        grp.visible = !Adwaita::StyleManager.default.system_supports_color_schemes?
      end
    end

    def behavior_group = @behavior_group ||= Adwaita::PreferencesGroup.new.tap { |grp| grp.title = _("Behavior") }

    def dark_row
      @dark_row ||= Adwaita::SwitchRow.new.tap do |row|
        row.title = _("Dark Mode")
        row.active = Settings.get.dark_mode
      end
    end

    def autostart_row = @autostart_row ||= Adwaita::SwitchRow.new.tap { |row| row.title = _("Autostart in Background") }

    def start_paused_row
      @start_paused_row ||= Adwaita::SwitchRow.new.tap do |row|
        row.title = _("Always Start on Pause")
        Settings.get.settings.bind(
          "start-paused",
          row,
          "active",
          Gio::SettingsBindFlags::DEFAULT,
        )
      end
    end

    def inhibition_row
      @inhibition_row ||= Adwaita::SwitchRow.new.tap do |row|
        row.title = _("Inhibit suspension while playing")
        Settings.get.settings.bind(
          "inhibit-suspension",
          row,
          "active",
          Gio::SettingsBindFlags::DEFAULT,
        )
      end
    end

    private

      def on_dark_toggled
        Settings.get.dark_mode = dark_row.active?

        if dark_row.active?
          Adwaita::StyleManager.default.color_scheme = :force_dark
        else
          Adwaita::StyleManager.default.color_scheme = :prefer_light
        end
      end
  end
end
