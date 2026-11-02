# frozen_string_literal: true

require "gtk4"
require "adwaita"
require_relative "about_dialog"
require_relative "define"
require_relative "preset"
require_relative "preset_chooser"
require_relative "preset_dialog"
require_relative "settings"
require_relative "shortcuts_dialog"

module Blanket
  # The port's application, ported from the parts of blanket/main.py that set
  # up the application object: the style manager's dark-mode fallback, the
  # stylesheet, the actions and their accelerators, the window's saved state
  # and the background-playback behaviour on close.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    def build
      app.tap do
        app.signal_connect("startup") { on_startup }

        app.signal_connect("activate") do
          window.tap do |win|
            win.content = toolbar_view
            win.hide_on_close = settings.background

            win.add_action(close_action)
            win.signal_connect("close-request") { on_close_request }
          end

          toolbar_view.tap do |view|
            view.add_top_bar(header_bar)
            view.content = status_page

            header_bar.tap do |bar|
              bar.title_widget = presets_chooser.build
              bar.pack_end(menu_button)
            end
          end

          window.present
        end

        app.signal_connect("shutdown") { settings.save_presets }
      end
    end

    def run = app.run([])

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new(Define::APP_ID, :default_flags)

    def window
      @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
        win.title = "Blanket"
        win.icon_name = Define::APP_ID
        win.set_default_size(window_state[:width], window_state[:height])

        if window_state[:maximized]
          win.maximize
        end
      end
    end

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "open-menu-symbolic"
        button.tooltip_text = "Main Menu"
        button.primary = true
        button.menu_model = primary_menu
      end
    end

    # Ported from window.blp's primary-menu. "Save as New Preset…" sits in the
    # sounds view's more-menu upstream, which belongs to window.blp; it is
    # carried here so the action reaches the preset chooser.
    def primary_menu
      @primary_menu ||= Gio::Menu.new.tap do |menu|
        menu.append_section(nil, playback_section)
        menu.append_section(nil, presets_section)
        menu.append_section(nil, app_section)
        menu.append_section(nil, quit_section)
      end
    end

    def playback_section
      @playback_section ||= Gio::Menu.new.tap do |menu|
        menu.append("Keep Playing when Closed", "app.background-playback")
      end
    end

    def presets_section
      @presets_section ||= Gio::Menu.new.tap do |menu|
        menu.append("Save as New Preset…", "app.add-preset")
      end
    end

    def app_section
      @app_section ||= Gio::Menu.new.tap do |menu|
        menu.append("Keyboard Shortcuts", "app.shortcuts")
        menu.append("About Blanket", "app.about")
      end
    end

    def quit_section
      @quit_section ||= Gio::Menu.new.tap { |menu| menu.append("Quit", "app.quit") }
    end

    def presets_chooser = @presets_chooser ||= PresetChooser.new(window)

    def status_page
      @status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.title = "Blanket"
        page.description = "Listen to different sounds"
        page.icon_name = Define::APP_ID
      end
    end

    def css_provider
      @css_provider ||= Gtk::CssProvider.new.tap do |provider|
        provider.load_from_path(Define::STYLE_PATH)
      end
    end

    def close_action
      @close_action ||= Gio::SimpleAction.new("close", nil).tap do |action|
        action.signal_connect("activate") { window.close }
      end
    end

    def quit_action
      @quit_action ||= Gio::SimpleAction.new("quit", nil).tap do |action|
        action.signal_connect("activate") { app.quit }
      end
    end

    def about_action
      @about_action ||= Gio::SimpleAction.new("about", nil).tap do |action|
        action.signal_connect("activate") { AboutDialog.new.present(window) }
      end
    end

    def shortcuts_action
      @shortcuts_action ||= Gio::SimpleAction.new("shortcuts", nil).tap do |action|
        action.signal_connect("activate") { ShortcutsDialog.new.present(window) }
      end
    end

    def add_preset_action
      @add_preset_action ||= Gio::SimpleAction.new("add-preset", nil).tap do |action|
        action.signal_connect("activate") { open_preset_dialog }
      end
    end

    def background_action
      @background_action ||= Gio::SimpleAction.new(
        "background-playback",
        nil,
        GLib::Variant.new(settings.background),
      ).tap do |action|
        action.signal_connect("change-state") { |simple, value| on_background(simple, value) }
      end
    end

    private

      def settings = Settings.get

      def window_state = @window_state ||= settings.window_state

      def on_startup
        style_manager.tap do |manager|
          if settings.dark_mode && !manager.system_supports_color_schemes?
            manager.color_scheme = :force_dark
          end
        end

        icon_theme.add_search_path(Define::ICONS_DIR)

        Gtk::StyleContext.add_provider_for_display(
          Gdk::Display.default,
          css_provider,
          Gtk::StyleProvider::PRIORITY_APPLICATION,
        )

        [
          quit_action,
          about_action,
          shortcuts_action,
          add_preset_action,
          background_action,
        ].each { |action| app.add_action(action) }

        {
          "app.quit"      => ["<Control>q"],
          "app.shortcuts" => ["<Control>question"],
          "win.close"     => ["<Control>w"],
        }.each { |action, accels| app.set_accels_for_action(action, accels) }
      end

      def style_manager = Adwaita::StyleManager.default

      def icon_theme = Gtk::IconTheme.get_for_display(Gdk::Display.default)

      def open_preset_dialog
        PresetDialog.new(on_created: ->(preset) { preset.activate }).present(window)
      end

      def on_background(action, value)
        action.set_state(value)
        settings.background = value.value
        window.hide_on_close = value.value
      end

      # Ported from main.py's _on_window_close_request: with background
      # playback on, closing the window only hides it.
      def on_close_request
        save_window_state

        if settings.background
          settings.save_presets
          window.visible = false
          true
        else
          settings.save_presets
          false
        end
      end

      # Ported from window.py's save_window_state: the size recorded while the
      # window is maximized is the one it had before, so restoring it gives
      # back the size the user chose.
      def save_window_state
        window.maximized?.then do |maximized|
          if maximized
            settings.set_window_state(
              width:     window_state[:width],
              height:    window_state[:height],
              maximized: true,
            )
          else
            settings.set_window_state(
              width:     window.width,
              height:    window.height,
              maximized: false,
            )
          end
        end
      end
  end
end
