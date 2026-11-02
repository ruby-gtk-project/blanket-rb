# frozen_string_literal: true

require "json"
require "securerandom"
require "gio2"
require_relative "define"

module Blanket
  # Ported from blanket/settings.py.
  #
  # Upstream subclasses Gio.Settings and adds a custom "preset-changed"
  # signal. Defining a GObject signal on a Ruby subclass of Gio::Settings is
  # not something the Ruby bindings support, so this wraps a Gio::Settings
  # instead and keeps the signal as a list of blocks — the only callers are in
  # this port, and they all want "run this when the active preset changes".
  #
  # The schema's dictionary and tuple keys hold JSON here rather than a
  # GVariant dict: Ruby's GVariant bindings raise NotImplementedError
  # converting either shape in either direction. See the comment at the top of
  # data/schemas/org.rubygtkproject.Blanket.gschema.xml.
  class Settings
    DEFAULT_WINDOW_WIDTH = 520
    DEFAULT_WINDOW_HEIGHT = 600

    def self.get = @get ||= new

    def initialize
      @settings = Gio::Settings.new(Define::APP_ID)
      @presets_settings = {}
      @preset_changed_callbacks = []
      migrate_legacy_volumes
    end

    # The wrapped Gio::Settings, for the callers that bind a widget property
    # straight to a key or create a stateful action from one.
    attr_reader :settings

    # Runs the block whenever the named key changes. Upstream writes
    # `connect("changed::autostart", ...)`.
    def on_changed(key, &block) = settings.signal_connect("changed::#{key}") { |_s, _k| block.call }

    # Runs the block whenever the active preset changes. Upstream's custom
    # "preset-changed" signal.
    def on_preset_changed(&block) = @preset_changed_callbacks << block

    # Autostart

    def autostart = settings.get_boolean("autostart")

    def autostart=(value)
      settings.set_boolean("autostart", value)
    end

    # Start in Pause

    def start_paused = settings.get_boolean("start-paused")

    def start_paused=(value)
      settings.set_boolean("start-paused", value)
    end

    # Dark Mode

    def dark_mode = settings.get_boolean("dark-mode")

    def dark_mode=(value)
      settings.set_boolean("dark-mode", value)
    end

    # Inhibit suspension

    def inhibit_suspension = settings.get_boolean("inhibit-suspension")

    def inhibit_suspension=(value)
      settings.set_boolean("inhibit-suspension", value)
    end

    # Sounds view scroll position

    def scroll_position = settings.get_double("scroll-position")

    def scroll_position=(value)
      settings.set_double("scroll-position", value)
    end

    # General volume level

    def volume = settings.get_double("volume")

    def volume=(value)
      settings.set_double("volume", value)
    end

    # Playing state

    def playing = settings.get_boolean("playing")

    def playing=(value)
      settings.set_boolean("playing", value)
    end

    # Background playing

    def background = settings.get_boolean("background-playback")

    def background=(value)
      settings.set_boolean("background-playback", value)
    end

    # Window state. Upstream stores a (iib) tuple; this is the same three
    # values as a JSON array.

    def window_state
      read_json("window-state", @settings, [-1, -1, false]).then do |state|
        width, height, maximized = state
        {
          width:     width.to_i.negative? ? DEFAULT_WINDOW_WIDTH : width.to_i,
          height:    height.to_i.negative? ? DEFAULT_WINDOW_HEIGHT : height.to_i,
          maximized: maximized ? true : false,
        }
      end
    end

    def set_window_state(width:, height:, maximized:)
      write_json("window-state", @settings, [width, height, maximized])
    end

    # Custom sounds

    def custom_audios = read_json("custom-audios", @settings, {})

    def custom_audios=(audios)
      write_json("custom-audios", @settings, audios)
    end

    # Custom sounds helper functions

    def add_custom_audio(name, uri)
      custom_audios.then do |saved|
        unless saved.key?(name)
          self.custom_audios = saved.merge(name => uri)
        end
      end
    end

    def remove_custom_audio(name)
      custom_audios.then do |saved|
        if saved.key?(name)
          self.custom_audios = saved.except(name)
        end
      end
    end

    def rename_custom_audio(old_name, new_name)
      custom_audios.then do |saved|
        if saved.key?(old_name) && !saved.key?(new_name)
          self.custom_audios = saved.except(old_name).merge(new_name => saved[old_name])
        end
      end
    end

    # Presets

    def presets = settings.get_strv("presets")

    def presets=(ids)
      settings.set_strv("presets", ids)
    end

    def active_preset = settings.get_string("active-preset")

    def active_preset=(preset_id)
      settings.set_string("active-preset", preset_id)
      @preset_changed_callbacks.each { |callback| callback.call(preset_id) }
    end

    def active_preset_name = get_preset_name(active_preset)

    # The id of the preset that ships with the schema, which cannot be
    # renamed or removed.
    def default_preset = settings.get_default_value("active-preset")

    # Presets helper functions

    # The presets as id => name, in the order they are shown.
    def get_presets_dict = presets.to_h { |preset_id| [preset_id, get_preset_name(preset_id)] }

    # Creates a preset holding a copy of the active preset's volumes, and
    # returns its id.
    def add_preset(name)
      SecureRandom.uuid.tap do |preset_id|
        self.presets = presets + [preset_id]
        set_preset_name(preset_id, name)
        set_preset_volumes(preset_id, get_preset_volumes(active_preset))
        set_preset_mutes(preset_id, get_preset_mutes(active_preset))
      end
    end

    # Removes a preset and returns the index it occupied, or nil when it was
    # not a known preset.
    def remove_preset(preset_id)
      presets.index(preset_id).then do |index|
        unless index.nil?
          self.presets = presets - [preset_id]
          @presets_settings.delete(preset_id)
        end
        index
      end
    end

    def get_preset_name(preset_id) = get_preset_settings(preset_id).get_string("visible-name")

    def set_preset_name(preset_id, name)
      get_preset_settings(preset_id).tap do |preset|
        preset.set_string("visible-name", name)
        preset.apply # Always apply changes on name change
      end
    end

    def get_preset_volumes(preset_id) = read_json("sounds-volume", get_preset_settings(preset_id), {})

    def set_preset_volumes(preset_id, volumes)
      write_json("sounds-volume", get_preset_settings(preset_id), volumes)
    end

    def get_preset_mutes(preset_id) = read_json("sounds-mute", get_preset_settings(preset_id), {})

    def set_preset_mutes(preset_id, mutes)
      write_json("sounds-mute", get_preset_settings(preset_id), mutes)
    end

    def get_preset_hide_inactive(preset_id)
      get_preset_settings(preset_id).get_boolean("hide-inactive")
    end

    def set_preset_hide_inactive(preset_id, hide)
      get_preset_settings(preset_id).set_boolean("hide-inactive", hide)
    end

    # Preset sound volume

    def get_sound_volume(name) = get_preset_volumes(active_preset).fetch(name, 0.0).to_f

    def set_sound_volume(name, volume)
      set_preset_volumes(active_preset, get_preset_volumes(active_preset).merge(name => volume))

      if volume.zero?
        set_sound_mute(name, false)
      end
    end

    # Preset sound mute

    def get_sound_mute(name) = get_preset_mutes(active_preset).fetch(name, true) ? true : false

    def set_sound_mute(name, mute)
      set_preset_mutes(active_preset, get_preset_mutes(active_preset).merge(name => mute))
    end

    # Preset settings helper functions

    # The Gio::Settings for one preset, kept in delay-apply mode so a run of
    # volume changes is written once, when save_presets is called.
    def get_preset_settings(preset_id = nil)
      (preset_id || active_preset).then do |id|
        @presets_settings[id] ||= Gio::Settings.new(
          "#{Define::APP_ID}.preset",
          path: preset_path(id),
        ).tap(&:delay)
      end
    end

    # Applies the changes made to every preset, or to one named preset.
    def save_presets(preset_id = nil)
      if preset_id.nil?
        @presets_settings.each_value(&:apply)
      else
        @presets_settings[preset_id]&.apply
      end
    end

    # Legacy sounds volume

    def legacy_sounds_volume = read_json("sounds-volume", @settings, {})

    def legacy_sounds_volume=(volumes)
      write_json("sounds-volume", @settings, volumes)
    end

    # Moves the volumes written by releases that predate presets into the
    # default preset.
    def migrate_legacy_volumes
      legacy_sounds_volume.then do |legacy|
        unless legacy.empty?
          set_preset_volumes(default_preset, legacy)
          save_presets(default_preset)
          self.legacy_sounds_volume = {}
        end
      end
    end

    private

      def preset_path(preset_id)
        settings.path.then do |path|
          path.end_with?("/") ? "#{path}#{preset_id}/" : "#{path}/#{preset_id}/"
        end
      end

      def read_json(key, source, fallback)
        JSON.parse(source.get_string(key))
      rescue JSON::ParserError
        fallback
      end

      def write_json(key, target, value) = target.set_string(key, JSON.generate(value))
  end
end
