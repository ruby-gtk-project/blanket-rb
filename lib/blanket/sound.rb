# frozen_string_literal: true

require "gstreamer"
require_relative "audio/bins"
require_relative "define"
require_relative "main_player"
require_relative "settings"

module Blanket
  # Ported from blanket/sound.py.
  #
  # One sound: its name, title and icon, whether it is playing, whether it
  # failed, and the volume the active preset saved for it. The GStreamer branch
  # behind it is attached to the shared pipeline only while the sound is
  # audible, and is released five seconds after it goes quiet.
  #
  # Upstream is a GObject whose properties the window binds to the tile and the
  # volume row. Ruby-defined GObject properties are not worth the plumbing here
  # — see the note on Preset — so this is a plain object and the widgets refresh
  # from the blocks given to #on_changed, which is what the bindings were for.
  class Sound
    # Seconds an inaudible sound keeps its decoder before it is released.
    DETACH_DELAY = 5

    attr_reader :name, :uri, :noise, :custom

    def initialize(name, uri: nil, title: nil, noise: false, custom: false, failed: false, error_message: nil)
      @name = name
      @uri = uri || Define.sound_uri(name)
      @title = title || name
      @icon_name = icon_for(name, custom)
      @error_message = error_message || ""
      @noise = noise
      @custom = custom
      @failed = failed
      @playing = false
      @removed = false
      @player = nil
      @mixer_pad = nil
      @detach_id = 0
      @callbacks = []

      unless saved_mute || failed?
        self.playing = true
      end
    end

    attr_reader :title, :icon_name, :error_message

    # Runs the block whenever anything the tile or the volume row shows moves:
    # the title, the icon, the playing state, the failed state or the volume.
    def on_changed(&block) = @callbacks << block

    def title=(value)
      @title = value
      changed
    end

    def name=(value)
      @name = value
      changed
    end

    def playing? = @playing

    # Ported from _playing_changed: a sound turned on at volume zero is given
    # a usable one, and the playing state is saved as the preset's mute flag.
    def playing=(value)
      unless @removed || value == @playing
        @playing = value

        if value
          if saved_volume.zero?
            self.saved_volume = 0.5
          end

          @player&.volume = saved_volume
        end

        self.saved_mute = !value
        update_playback
        changed
      end
    end

    def failed? = @failed

    def failed=(value)
      @failed = value

      if playing? && value
        self.playing = false
      end

      changed
    end

    def saved_volume = Settings.get.get_sound_volume(name)

    def saved_volume=(volume)
      unless @removed
        volume.round(2).then do |rounded|
          @player&.volume = rounded
          Settings.get.set_sound_volume(name, rounded)

          if !rounded.zero? && !playing?
            self.playing = true
          end

          changed
        end
      end
    end

    def saved_mute = Settings.get.get_sound_mute(name)

    def saved_mute=(mute)
      Settings.get.set_sound_mute(name, mute)
    end

    # Removes a custom sound: its branch goes away now rather than on the
    # detach delay, its entry leaves the custom-audios setting, and every
    # setter afterwards is a no-op — a removed sound still reachable from a
    # widget would otherwise write volumes back into the preset.
    def remove
      if custom
        @removed = true
        cancel_detach
        detach
        Settings.get.remove_custom_audio(name)
      end
    end

    # Tears the branch down without waiting for the stream to go idle.
    def release_now
      cancel_detach
      detach
    end

    # Plays the sound immediately.
    def play_now = playback_up

    # The branch currently in the pipeline, or nil. MainPlayer reads it to find
    # which sound an erroring element belongs to.
    attr_reader :player

    # Called by MainPlayer on every sound it holds when the active preset
    # changes. Upstream connects to the player's "preset-changed" signal in
    # each sound; here the player walks its own list, so a sound dropped from
    # that list stops hearing about it — which is what upstream's disconnect in
    # Sound.remove is for.
    def preset_changed
      @playing = !saved_mute
      update_playback
      changed
    end

    # Called by MainPlayer on every sound it holds for "reset-volumes".
    def reset_volumes
      self.saved_volume = 0.0
      self.playing = false
    end

    # Called by MainPlayer on every sound it holds when its own playing state
    # moves.
    def main_player_playing_changed = update_playback

    private

      def icon_for(name, custom)
        if custom
          "blanket-sound-wave-symbolic"
        else
          "blanket-#{name}-symbolic"
        end
      end

      def changed = @callbacks.each(&:call)

      # Ported from _update_playback: a sound is audible only when both it and
      # the main player are playing and its volume is above zero.
      def update_playback
        if playing? && MainPlayer.get.playing? && saved_volume.positive?
          playback_up
        elsif MainPlayer.get.playing?
          playback_down
        end
      end

      def playback_up
        unless failed?
          cancel_detach

          if @player.nil?
            attach
          end

          @player&.volume = saved_volume
        end
      end

      def playback_down
        unless @player.nil?
          @player.volume = 0
          schedule_detach
        end
      end

      def schedule_detach
        unless @player.nil? || @detach_id.positive?
          @detach_id = GLib::Timeout.add_seconds(DETACH_DELAY) do
            @detach_id = 0
            detach
            false
          end
        end
      end

      def cancel_detach
        if @detach_id.positive?
          GLib::Source.remove(@detach_id)
          @detach_id = 0
        end
      end

      def detach
        unless @player.nil? || @mixer_pad.nil?
          MainPlayer.get.detach_sound_bin(@player, @mixer_pad)
          @mixer_pad = nil
          @player = nil
        end
      end

      def attach
        if @player.nil?
          new_bin.tap do |sound_bin|
            sound_bin.build
            @player = sound_bin
            @mixer_pad = MainPlayer.get.attach_sound_bin(sound_bin)
          end
        end
      end

      def new_bin
        if noise
          Audio::NoiseBin.new(name)
        else
          Audio::LoopBin.new(name, uri)
        end
      end
  end
end
