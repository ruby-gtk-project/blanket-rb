# frozen_string_literal: true

require "gtk4"
require "adwaita"
require_relative "about_dialog"
require_relative "define"
require_relative "main_player"
require_relative "mpris"
require_relative "preferences_dialog"
require_relative "preset"
require_relative "preset_dialog"
require_relative "settings"
require_relative "shortcuts_dialog"
require_relative "sound"
require_relative "sound_rename_dialog"
require_relative "window"

module Blanket
  # Ported from blanket/main.py.
  #
  # Owns the application object itself: startup (style manager fallback,
  # the stylesheet, MPRIS, every app-scoped action and its accelerators),
  # activation (building and presenting the one Window), and shutdown
  # (saving settings and stopping the shared pipeline). Everything that is
  # the window's own content — the header bar, the sounds grid, the volume
  # popover — lives in Window, ported from window.py/window.blp.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    def initialize
      @window_hidden = false
      @window_built = false
    end

    def build
      app.tap do
        app.add_main_option(
          "hidden",
          "h".ord,
          GLib::OptionFlags::NONE,
          GLib::OptionArg::NONE,
          "Start window hidden",
          nil,
        )
        app.signal_connect("startup") { on_startup }
        app.signal_connect("command-line") { |_app, command_line| on_command_line(command_line) }
        app.signal_connect("activate") { on_activate }
        app.signal_connect("shutdown") { on_shutdown }
      end
    end

    # GApplication#run expects argv[0] to be the program name, the way C's
    # argv does; Ruby's ARGV has already stripped it, so it is put back or
    # the first real argument (e.g. --hidden) gets eaten as if it were one.
    def run = app.run([$PROGRAM_NAME, *ARGV])

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    #
    # :handles_command_line replaces main.py's
    # Gio::ApplicationFlags::HANDLES_COMMAND_LINE: with it set, GApplication
    # no longer calls "activate" on its own, which is why #on_command_line
    # below calls it explicitly.
    def app = @app ||= Gtk::Application.new(Define::APP_ID, :handles_command_line)

    def css_provider
      @css_provider ||= Gtk::CssProvider.new.tap do |provider|
        provider.load_from_path(Define::STYLE_PATH)
      end
    end

    def mpris = @mpris ||= Mpris.new(self)

    def quit_action
      @quit_action ||= Gio::SimpleAction.new("quit", nil).tap do |action|
        action.signal_connect("activate") { on_quit }
      end
    end

    def about_action
      @about_action ||= Gio::SimpleAction.new("about", nil).tap do |action|
        action.signal_connect("activate") { AboutDialog.new.present(blanket_window.window) }
      end
    end

    def preferences_action
      @preferences_action ||= Gio::SimpleAction.new("preferences", nil).tap do |action|
        action.signal_connect("activate") { PreferencesDialog.new(blanket_window.window).present(blanket_window.window) }
      end
    end

    def shortcuts_action
      @shortcuts_action ||= Gio::SimpleAction.new("shortcuts", nil).tap do |action|
        action.signal_connect("activate") { ShortcutsDialog.new.present(blanket_window.window) }
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

    def playpause_action
      @playpause_action ||= Gio::SimpleAction.new("playpause", nil).tap do |action|
        action.signal_connect("activate") { on_playpause }
      end
    end

    def play_action
      @play_action ||= Gio::SimpleAction.new("play", nil).tap do |action|
        action.signal_connect("activate") { on_play }
      end
    end

    def add_preset_action
      @add_preset_action ||= Gio::SimpleAction.new("add-preset", nil).tap do |action|
        action.signal_connect("activate") { PresetDialog.new.present(blanket_window.window) }
      end
    end

    def reset_volumes_action
      @reset_volumes_action ||= Gio::SimpleAction.new("reset-volumes", nil).tap do |action|
        action.signal_connect("activate") { MainPlayer.get.reset_volumes }
      end
    end

    def open_action
      @open_action ||= Gio::SimpleAction.new("open", nil).tap do |action|
        action.signal_connect("activate") { blanket_window.open_audio }
      end
    end

    def remove_sound_action
      @remove_sound_action ||= Gio::SimpleAction.new("remove-sound", GLib::VariantType.new("u")).tap do |action|
        action.signal_connect("activate") { |_action, index_variant| on_remove_sound(index_variant) }
      end
    end

    def rename_sound_action
      @rename_sound_action ||= Gio::SimpleAction.new("rename-sound", GLib::VariantType.new("u")).tap do |action|
        action.signal_connect("activate") { |_action, index_variant| on_rename_sound(index_variant) }
      end
    end

    # Called by Mpris#Raise and Mpris#Quit, and by the window actions they
    # otherwise reach directly, through the window the player is shared
    # with rather than the application object MPRIS is given.
    def on_raise = blanket_window.window.present

    def on_playpause
      MainPlayer.get.playing = !MainPlayer.get.playing?
      blanket_window.hide_power_toast
    end

    def on_play
      MainPlayer.get.playing = true
      blanket_window.hide_power_toast
    end

    def on_pause
      MainPlayer.get.playing = false
      blanket_window.hide_power_toast
    end

    def on_quit = app.quit

    private

      def settings = Settings.get

      def blanket_window = @blanket_window ||= Window.new(self)

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

        mpris.build

        [
          quit_action,
          about_action,
          preferences_action,
          background_action,
          playpause_action,
          play_action,
          add_preset_action,
          reset_volumes_action,
          open_action,
          remove_sound_action,
          rename_sound_action,
          shortcuts_action,
        ].each { |action| app.add_action(action) }

        {
          "app.quit"          => ["<Control>q"],
          "app.preferences"   => ["<Control>comma"],
          "app.playpause"     => ["<Control>m", "space"],
          "app.open"          => ["<Control>o"],
          "app.shortcuts"     => ["<Control>question"],
          "win.close"         => ["<Control>w"],
          "win.hide-inactive" => ["<Control>h"],
        }.each { |action, accels| app.set_accels_for_action(action, accels) }
      end

      def on_activate
        blanket_window.build.tap do |win|
          win.hide_on_close = settings.background
          win.signal_connect("close-request") { on_close_request }
        end

        if @window_hidden
          blanket_window.window.visible = false
          @window_hidden = false
        else
          blanket_window.present
        end

        MainPlayer.get.volume = settings.volume
        MainPlayer.get.playing = settings.playing && !settings.start_paused
      end

      # Ported from main.py's do_command_line: with :handles_command_line
      # set on the application, GApplication no longer calls "activate" on
      # its own, so this calls it explicitly once the --hidden option (if
      # any) has been read off the command line.
      def on_command_line(command_line)
        if command_line.options_dict.contains?("hidden") && !@window_built
          @window_hidden = true
        end
        @window_built = true
        app.activate
        0
      end

      def on_shutdown
        save_settings
        MainPlayer.get.stop
      end

      def style_manager = Adwaita::StyleManager.default

      def icon_theme = Gtk::IconTheme.get_for_display(Gdk::Display.default)

      # `value` arrives already unwrapped to a Ruby boolean: GSimpleAction's
      # "change-state" signal hands a scalar-typed parameter through as its
      # native Ruby value here, not as a GLib::Variant, while #set_state
      # wants an actual GLib::Variant back.
      def on_background(action, value)
        action.set_state(GLib::Variant.new(value))
        settings.background = value
        blanket_window.window.hide_on_close = value
      end

      # `index` arrives already unwrapped to a Ruby Integer: GSimpleAction's
      # "activate" signal hands a scalar-typed parameter through as its
      # native Ruby value rather than as a GLib::Variant, unlike
      # "change-state"'s value parameter below.
      def on_remove_sound(index)
        MainPlayer.get.get_by_index(index).then do |sound|
          unless sound.nil?
            sound.remove
            MainPlayer.get.remove(index)
          end
        end
      end

      def on_rename_sound(index)
        MainPlayer.get.get_by_index(index).then do |sound|
          unless sound.nil?
            SoundRenameDialog.new(
              sound,
              index,
              on_space_unset: -> { unset_space_accel },
              on_space_reset: -> { set_space_accel },
            ).present(blanket_window.window)
          end
        end
      end

      def set_space_accel = app.set_accels_for_action("app.playpause", ["<Control>m", "space"])
      def unset_space_accel = app.set_accels_for_action("app.playpause", ["<Control>m"])

      def save_settings
        settings.volume = MainPlayer.get.volume
        settings.playing = MainPlayer.get.playing?
        settings.save_presets
      end

      # Ported from main.py's _on_window_close_request: with background
      # playback on, closing the window only hides it.
      def on_close_request
        blanket_window.save_window_state

        if settings.background
          save_settings
          blanket_window.window.visible = false
          true
        else
          save_settings
          false
        end
      end
  end
end
