# frozen_string_literal: true

require "adwaita"
require "gio2"
require "securerandom"
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
  #
  # `ashpd` (the gem the gemspec briefly declared) binds Account, Camera,
  # OpenUri, Screenshot, Settings and Trash — checked with
  # `Ashpd.constants.sort` in nix develop — but not Background, and was
  # removed again (`ab7a2a8`). `Xdp`/`libportal` has no Ruby binding at all.
  # Both are themselves thin wrappers over one D-Bus call, so this talks to
  # the portal directly on the session bus with `gio2`, which every other
  # D-Bus user in this port (`mpris.rb`) already depends on:
  #
  # 1. `org.freedesktop.portal.Background.RequestBackground` is called on
  #    `org.freedesktop.portal.Desktop`, with a `handle_token` in its options
  #    so the reply object's path is known before the call returns.
  # 2. That path is `org.freedesktop.portal.Request`'s `Response` signal is
  #    subscribed on *before* the call is sent, so a portal that answers
  #    instantly cannot race the subscription.
  # 3. The signal's first argument is the response code — `0` means granted.
  #    Denial shows the same "Authorization failed" alert upstream shows and
  #    reverts the switch; a call that fails outright (no portal running
  #    at all, as on a plain desktop session with no xdg-desktop-portal, or
  #    outside a sandbox) shows the same toast upstream shows on an
  #    exception and reverts the switch too.
  class PreferencesDialog
    include GetText

    def initialize(window)
      @window = window
      @autostart_saved = Settings.get.autostart
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
        autostart_row.signal_connect("notify::active") { on_autostart_toggled }
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

    def autostart_row
      @autostart_row ||= Adwaita::SwitchRow.new.tap do |row|
        row.title = _("Autostart in Background")
        row.active = @autostart_saved
      end
    end

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

      def on_autostart_toggled = request_autostart(autostart_row.active?)

      def bus = @bus ||= Gio.bus_get_sync(Gio::BusType::SESSION)

      # Escapes the connection's own unique name the way xdg-desktop-portal
      # escapes it when it builds a Request object's path: the leading `:`
      # dropped, every `.` turned into `_`.
      def sender_path_segment = bus.unique_name.delete_prefix(":").gsub(".", "_")

      def request_background_options(token, active)
        reason = _("Autostart Blanket in background.").gsub('"', '\\"')
        commandline = %w[blanket --hidden].map { |arg| "\"#{arg}\"" }.join(", ")
        text = <<~VARIANT.chomp
          ("", {"handle_token": <"#{token}">, "reason": <"#{reason}">, "autostart": <#{active}>, "commandline": <[#{commandline}]>})
        VARIANT
        GLib::Variant.parse(text, "(sa{sv})")
      end

      def request_autostart(active)
        token = "blanket_#{SecureRandom.hex(16)}"
        request_path = "/org/freedesktop/portal/desktop/request/#{sender_path_segment}/#{token}"
        subscription = nil
        subscription = bus.signal_subscribe(
          nil,
          "org.freedesktop.portal.Request",
          "Response",
          request_path,
          nil,
          Gio::DBusSignalFlags::NONE,
        ) do |_connection, _sender, _path, _iface, _signal, parameters|
          bus.signal_unsubscribe(subscription)
          response_code, = parameters
          on_background_response(response_code, active)
        end

        bus.call(
          "org.freedesktop.portal.Desktop",
          "/org/freedesktop/portal/desktop",
          "org.freedesktop.portal.Background",
          "RequestBackground",
          request_background_options(token, active),
          GLib::VariantType.new("(o)"),
          Gio::DBusCallFlags::NONE,
          -1,
        ) do |connection, result|
          connection.call_finish(result)
        rescue StandardError
          bus.signal_unsubscribe(subscription)
          on_autostart_request_failed
        end
      end

      # `response_code` is 0 when the portal grants the request, 1 when the
      # user dismisses or denies it, 2 when the request was cancelled.
      def on_background_response(response_code, active)
        if response_code.zero?
          Settings.get.autostart = active
          @autostart_saved = active
        elsif active
          show_autostart_denied
        else
          Settings.get.autostart = active
          @autostart_saved = active
        end
      end

      def show_autostart_denied
        Adwaita::AlertDialog.new(
          _("Authorization failed"),
          _(
            "Make sure Blanket has permission to run in the background in " \
            "Settings → Applications → Blanket and try again.",
          ),
        ).tap do |alert|
          alert.add_response("ok", _("Ok"))
          alert.present(@window)
        end
        autostart_row.active = @autostart_saved
      end

      def on_autostart_request_failed
        dialog.add_toast(Adwaita::Toast.new(_("The autostart request failed.")))
        autostart_row.active = @autostart_saved
      end
  end
end
