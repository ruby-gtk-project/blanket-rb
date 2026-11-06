# frozen_string_literal: true

require "adwaita"
require "uri"
require_relative "define"
require_relative "dummy_item_model"
require_relative "main_player"
require_relative "play_pause_button"
require_relative "preset_chooser"
require_relative "settings"
require_relative "sound"
require_relative "sound_item"
require_relative "volume_row"

module Blanket
  # Ported from blanket/window.py and data/resources/window.blp.
  #
  # The main window: the sounds grid (with a trailing "Add…" tile), the
  # volume popover's per-sound sliders, and the preset chooser and main menu
  # in the header bar.
  #
  # Upstream binds a Gtk.FilterListModel of MainPlayer straight to the
  # FlowBox and rebuilds nothing by hand; MainPlayer cannot be a real
  # Gio.ListModel here for the reason its own file documents, so the grid
  # and volume list are rebuilt from MainPlayer#to_a whenever anything that
  # would have changed the filtered model's contents fires: a sound added or
  # removed, any sound's own #on_changed, a preset switch, a volumes reset,
  # or the hide-inactive toggle.
  class Window
    # `app` answers #open_audio's file-picker modality and the window
    # actions this class does not itself define (close, hide-inactive are
    # here; everything else is app-scoped).
    def initialize(app)
      @app = app
      @items_by_sound = {}
      @tiles = []
      @tile_children = []
      @volume_rows = []
    end

    def build
      window.tap do |win|
        win.content = toolbar_view
        win.add_action(close_action)
        win.add_action(hide_inactive_action)

        toolbar_view.tap do |view|
          view.bottom_bar_style = :raised
          view.add_top_bar(header_bar)
          view.content = toast_overlay

          header_bar.tap do |bar|
            bar.title_widget = presets_chooser.build
            bar.pack_end(menu_button)
          end

          toast_overlay.tap do |overlay|
            overlay.child = scrolled

            scrolled.tap { |s| s.child = grid }
          end

          view.add_bottom_bar(action_bar)

          action_bar.tap do |bar|
            bar.center_widget = bottom_box

            bottom_box.tap do |box|
              box.append(volumes_button)
              box.append(playpause_btn.build)
              box.append(more_button)
            end
          end
        end

        Settings.get.on_changed("presets") { presets_chooser.refresh }
        MainPlayer.get.on_items_changed { |_pos, _removed, _added| refresh_lists }
        MainPlayer.get.on_playing_changed { |playing| playpause_btn.playing = playing }
        MainPlayer.get.on_preset_changed { |_preset| refresh_lists }
        MainPlayer.get.on_reset_volumes { refresh_lists }

        populate_sounds
        refresh_lists
      end
    end

    def present = window.present

    def window
      @window ||= Adwaita::ApplicationWindow.new(@app.app).tap do |win|
        win.width_request = 360
        win.height_request = 294
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
    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new

    def presets_chooser = @presets_chooser ||= PresetChooser.new(window)

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.menu_model = primary_menu
        button.icon_name = "open-menu-symbolic"
        button.tooltip_text = "Main Menu"
        button.primary = true
      end
    end

    # Ported from window.blp's primary-menu.
    def primary_menu
      @primary_menu ||= Gio::Menu.new.tap do |menu|
        menu.append_section(nil, playback_section)
        menu.append_section(nil, app_section)
        menu.append_section(nil, quit_section)
      end
    end

    def playback_section
      @playback_section ||= Gio::Menu.new.tap do |menu|
        menu.append("Keep Playing when Closed", "app.background-playback")
      end
    end

    def app_section
      @app_section ||= Gio::Menu.new.tap do |menu|
        menu.append("Preferences", "app.preferences")
        menu.append("Keyboard Shortcuts", "app.shortcuts")
        menu.append("About Blanket", "app.about")
      end
    end

    def quit_section
      @quit_section ||= Gio::Menu.new.tap { |menu| menu.append("Quit", "app.quit") }
    end

    def scrolled
      @scrolled ||= Gtk::ScrolledWindow.new.tap do |s|
        s.hscrollbar_policy = :never
        s.hexpand = true
        s.vexpand = true
      end
    end

    def grid
      @grid ||= Gtk::FlowBox.new.tap do |box|
        box.activate_on_single_click = true
        box.column_spacing = 12
        box.row_spacing = 12
        box.homogeneous = true
        box.selection_mode = :none
        box.valign = :start
        box.add_css_class("sound-view")

        box.signal_connect("child-activated") { |_grid, child| on_sound_activate(child) }
      end
    end

    def labels_group = @labels_group ||= Gtk::SizeGroup.new(:vertical)

    def action_bar = @action_bar ||= Gtk::ActionBar.new

    def bottom_box = @bottom_box ||= Gtk::Box.new(:horizontal, 24)

    def volumes_button
      @volumes_button ||= Gtk::MenuButton.new.tap do |button|
        button.popover = volumes_popover
        button.valign = :center
        button.icon_name = "audio-speakers-symbolic"
        button.direction = :up
        button.tooltip_text = "Volume Menu"
        button.add_css_class("circular")
      end
    end

    def playpause_btn = @playpause_btn ||= PlayPauseButton.new

    def more_button
      @more_button ||= Gtk::MenuButton.new.tap do |button|
        button.menu_model = more_menu
        button.valign = :center
        button.icon_name = "view-more-symbolic"
        button.direction = :up
        button.tooltip_text = "Sounds Menu"
        button.add_css_class("circular")
      end
    end

    def more_menu
      @more_menu ||= Gio::Menu.new.tap do |menu|
        menu.append_section(nil, hide_inactive_section)
        menu.append_section(nil, add_sound_section)
      end
    end

    def hide_inactive_section
      @hide_inactive_section ||= Gio::Menu.new.tap do |section|
        section.append("Hide Inactive Sounds", "win.hide-inactive")
        section.append("Save as New Preset…", "app.add-preset")
      end
    end

    def add_sound_section
      @add_sound_section ||= Gio::Menu.new.tap { |section| section.append("Add Sound…", "app.open") }
    end

    def volumes_popover
      @volumes_popover ||= Gtk::PopoverMenu.new.tap do |pop|
        pop.menu_model = volume_menu
        pop.width_request = 250
        pop.add_child(volumes_box, "volumes")
        pop.signal_connect("closed") { on_volumes_closed }
      end
    end

    def volume_menu
      @volume_menu ||= Gio::Menu.new.tap do |menu|
        menu.append_section(
          nil,
          Gio::Menu.new.tap do |section|
            section.append_item(Gio::MenuItem.new.tap { |item| item.set_attribute_value("custom", GLib::Variant.new("volumes")) })
          end,
        )
        menu.append_section(nil, Gio::Menu.new.tap { |section| section.append("Reset Sounds", "app.reset-volumes") })
      end
    end

    def volumes_box
      @volumes_box ||= Gtk::Box.new(:vertical, 6).tap do |box|
        box.append(volume_scale)
        box.append(volume_box)
      end
    end

    def volume_scale
      @volume_scale ||= Gtk::Scale.new(:horizontal, volume_adjustment).tap do |scale|
        scale.hexpand = true
        scale.draw_value = false
      end
    end

    def volume_adjustment
      @volume_adjustment ||= Gtk::Adjustment.new(
        MainPlayer.get.volume,
        0,
        1,
        0.01,
        0.01,
        0,
      ).tap do |adj|
        adj.signal_connect("value-changed") { MainPlayer.get.volume = adj.value }
      end
    end

    def volume_box
      @volume_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.visible = false
        box.append(Gtk::Separator.new(:horizontal).tap { |sep| sep.add_css_class("volume-separator") })
        box.append(volume_scrolled)
      end
    end

    def volume_scrolled
      @volume_scrolled ||= Gtk::ScrolledWindow.new.tap do |s|
        s.propagate_natural_height = true
        s.max_content_height = 320
        s.child = volume_list
      end
    end

    def volume_list = @volume_list ||= Gtk::ListBox.new.tap { |list| list.selection_mode = :none }

    def power_toast
      @power_toast ||= Adwaita::Toast.new("Paused to save power").tap do |toast|
        toast.action_name = "app.play"
        toast.button_label = "_Resume Playing"
        toast.timeout = 0
      end
    end

    def close_action
      @close_action ||= Gio::SimpleAction.new("close", nil).tap do |action|
        action.signal_connect("activate") { window.close }
      end
    end

    def hide_inactive_action
      @hide_inactive_action ||= Gio::SimpleAction.new(
        "hide-inactive",
        nil,
        GLib::Variant.new(hide_inactive?),
      ).tap do |action|
        action.signal_connect("change-state") { |simple, value| on_hide_inactive(simple, value) }
      end
    end

    # Opens the file picker upstream's open_audio builds, with the same five
    # audio types filtered by MIME, and appends whatever the user picks as a
    # new custom Sound.
    def open_audio
      Gtk::FileDialog.new.tap do |dialog|
        dialog.title = "Open audio"
        dialog.modal = true
        dialog.filters = audio_filters

        dialog.open_multiple(window, nil) { |_source, result| on_audio_chosen(dialog, result) }
      end
    end

    def show_power_toast = toast_overlay.add_toast(power_toast)
    def hide_power_toast = power_toast.dismiss

    def save_window_state
      if window.maximized?
        Settings.get.set_window_state(width: window_state[:width], height: window_state[:height], maximized: true)
      else
        Settings.get.set_window_state(width: window.width, height: window.height, maximized: false)
      end
    end

    private

      def window_state = @window_state ||= Settings.get.window_state

      AUDIO_FILTERS = {
        "Supported audio files" => %w[audio/ogg audio/flac audio/x-wav audio/wav audio/mpeg audio/aac],
        "Ogg"                   => %w[audio/ogg],
        "FLAC"                  => %w[audio/flac],
        "WAV"                   => %w[audio/x-wav audio/wav],
        "MP3"                   => %w[audio/mpeg],
        "AAC"                   => %w[audio/aac],
      }.freeze

      def audio_filters
        Gio::ListStore.new(Gtk::FileFilter).tap do |store|
          AUDIO_FILTERS.each do |name, mime_types|
            store.append(
              Gtk::FileFilter.new.tap do |filter|
                            filter.name = name
                            mime_types.each { |mime| filter.add_mime_type(mime) }
                          end,
            )
          end
        end
      end

      def on_audio_chosen(dialog, result)
        model = dialog.open_multiple_finish(result)

        (0...model.n_items).each do |position|
          gfile = model.get_item(position)
          filename = gfile.path

          unless filename.nil?
            basename = File.basename(filename)
            name = basename[0...basename.rindex(".")]
            uri = gfile.uri

            Sound.new(name, uri: uri, custom: true).tap do |sound|
              Settings.get.add_custom_audio(sound.name, sound.uri)
              append_sound(sound)
            end
          end
        end
      rescue GLib::Error => e
        warn("Error: #{e.message}")
      end

      def populate_sounds
        Define::SOUNDS.each do |group|
          group[:sounds].each { |s| append_sound(Sound.new(s[:name], title: s[:title])) }
        end

        Define::NOISES.each { |n| append_sound(Sound.new(n[:name], title: n[:title], noise: true)) }

        Settings.get.custom_audios.each do |name, uri|
          path = URI.decode_uri_component(URI.parse(uri).path.to_s)
          exists = File.exist?(path)

          append_sound(
            Sound.new(
              name,
              uri:           uri,
              custom:        true,
              failed:        !exists,
              error_message: exists ? nil : "File not found",
            ),
          )
        end
      end

      def append_sound(sound)
        sound.on_changed { refresh_lists }
        MainPlayer.get.append(sound)
      end

      def hide_inactive? = Settings.get.get_preset_hide_inactive(Settings.get.active_preset)

      # `value` arrives already unwrapped to a Ruby boolean — see the note
      # on Application#on_background — while #set_state wants an actual
      # GLib::Variant back.
      def on_hide_inactive(action, value)
        action.set_state(GLib::Variant.new(value))
        Settings.get.set_preset_hide_inactive(Settings.get.active_preset, value)
        refresh_lists
      end

      def on_volumes_closed
        MainPlayer.get.mute_vol_zero
        refresh_lists
      end

      def on_sound_activate(child)
        @tiles.find { |candidate, _item| candidate == child }.then do |found|
          unless found.nil?
            _candidate, item = found

            if item.sound.nil?
              open_audio
            elsif !item.sound.failed?
              item.sound.playing = !item.sound.playing?
            end

            refresh_lists
          end
        end
      end

      def sounds_for_grid
        if hide_inactive?
          MainPlayer.get.to_a.select(&:playing?)
        else
          MainPlayer.get.to_a
        end
      end

      def add_item
        @add_item ||= SoundItem.new(index: -> {}).tap do |item|
          labels_group.add_widget(item.label)
          item.build
          item.title = "Add…"
          item.icon_name = "blanket-add-symbolic"
        end
      end

      def refresh_lists
        refresh_grid
        refresh_volume_list
      end

      # Clears and repopulates the grid from the currently visible sounds.
      # Every sound keeps the same SoundItem across rebuilds — built once in
      # #tile_for and cached in @items_by_sound — so this only moves widgets
      # in and out of the grid. A fresh SoundItem per rebuild would also
      # subscribe a fresh #on_changed block on the sound every time, which
      # with no matching unsubscribe would grow that sound's callback list
      # without bound.
      def refresh_grid
        @tile_children.each { |child| grid.remove(child) }
        @tile_children = []
        @tiles = []

        sounds_for_grid.each { |sound| add_tile(tile_for(sound)) }
        add_tile(add_item)
      end

      def tile_for(sound)
        @items_by_sound[sound] ||= SoundItem.new(index: -> { MainPlayer.get.get_index(sound.name) }).tap do |item|
          labels_group.add_widget(item.label)
          item.build
          item.sound = sound
        end
      end

      def add_tile(item)
        item.child.tap do |child|
          grid.append(child)
          @tile_children << child
          @tiles << [child, item]
        end
      end

      def refresh_volume_list
        @volume_rows.each { |row| volume_list.remove(row.row) }

        @volume_rows = MainPlayer.get.to_a.select(&:playing?).map { |sound| volume_row_for(sound) }
        @volume_rows.each { |row| volume_list.append(row.row) }

        volume_box.visible = !@volume_rows.empty?
      end

      def volume_row_for(sound)
        VolumeRow.new.tap do |row|
          row.build
          row.title = sound.title
          row.volume = sound.saved_volume
          row.on_volume_changed { |value| sound.saved_volume = value }
        end
      end
  end
end
