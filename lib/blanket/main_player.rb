# frozen_string_literal: true

require "gstreamer"
require "gtk4"
require_relative "preset"
require_relative "settings"

module Blanket
  # Ported from blanket/main_player.py.
  #
  # Blanket's omnipresent player: one GStreamer pipeline shared by every sound,
  # and the list of sounds the window shows. Each audible sound is a branch
  # feeding an audiomixer, so all of them are decoded into one stream and go
  # out through a single audio sink.
  #
  # Upstream is a GObject that also implements Gio.ListModel, which the window
  # hands to FlowBox.bind_model. A Ruby class cannot implement a GInterface —
  # `type_register` leaves the GType carrying no interfaces, so GStreamer's and
  # GTK's `G_IS_LIST_MODEL` checks fail — so the sound list is plain Ruby here,
  # with #on_items_changed in place of the model's "items-changed" signal, and
  # the window builds its tiles itself.
  class MainPlayer
    def self.get = @get ||= new

    def initialize
      @sounds = []
      @branches = 0
      @detaching = []
      @playing = false
      @volume = 0.0
      @cookie = 0
      @items_changed_callbacks = []
      @playing_callbacks = []
      @preset_changed_callbacks = []
      @reset_volumes_callbacks = []

      Settings.get.on_preset_changed { |preset_id| handle_preset_changed(preset_id) }
      Settings.get.on_changed("inhibit-suspension") { on_settings_inhibition }

      setup_pipeline
    end

    # Playing state

    def playing? = @playing

    def playing=(value)
      unless value == @playing
        @playing = value
        sync_pipeline_state

        @sounds.each(&:main_player_playing_changed)

        if Settings.get.inhibit_suspension
          inhibit(value)
        end

        @playing_callbacks.each { |callback| callback.call(value) }
      end
    end

    def on_playing_changed(&block) = @playing_callbacks << block

    # Volume. The value here is the one the slider shows; the sink's volume is
    # the cube of it.
    #
    # Upstream binds the sink's "volume" to this property through
    # GstAudio.StreamVolume.convert_volume, which is a cube root one way and a
    # cube the other. The gstreamer gem loads only the Gst typelib, not
    # GstAudio, so the two conversions are written out here.

    attr_reader :volume

    def volume=(value)
      value.clamp(0.0, 1.0).then do |level|
        @volume = level
        sink_volume.set_property("volume", level**3)
      end
    end

    # Pipeline

    def setup_pipeline
      pipeline.tap do |line|
        elements.each { |element| line.add(element) }
        elements.each_cons(2) { |source, target| source.link(target) }

        line.bus.tap do |bus|
          bus.add_signal_watch
          bus.signal_connect("message::error") { |_bus, message| on_pipeline_error(message) }
        end
      end
    end

    def pipeline = @pipeline ||= Gst::Pipeline.new("blanket")
    def mixer = @mixer ||= Gst::ElementFactory.make("audiomixer", "mixer")
    def convert = @convert ||= Gst::ElementFactory.make("audioconvert", nil)
    def resample = @resample ||= Gst::ElementFactory.make("audioresample", nil)
    def sink_volume = @sink_volume ||= Gst::ElementFactory.make("volume", nil)
    def sink = @sink ||= Gst::ElementFactory.make("autoaudiosink", nil)

    # Attaches a sound's branch to the pipeline mixer and returns the mixer pad
    # it feeds, or nil when the mixer refused one.
    def attach_sound_bin(sound_bin)
      pipeline.add(sound_bin.bin)

      [mixer.request_pad_simple("sink_%u"), sound_bin.bin.get_static_pad("src")].then do |mixer_pad, src_pad|
        if mixer_pad.nil? || src_pad.nil?
          nil
        else
          link_branch(sound_bin, src_pad, mixer_pad)
        end
      end
    end

    # Detaches a sound's branch from the pipeline mixer.
    def detach_sound_bin(sound_bin, mixer_pad)
      # A branch unlinked while it still runs reports a not-linked error on its
      # way out; that one is expected.
      @detaching << sound_bin.bin

      if pipeline_state == Gst::State::PLAYING
        # Block the branch before tearing it down, so the mixer never sees a
        # half-removed pad.
        sound_bin.bin.get_static_pad("src")&.add_probe(Gst::PadProbeType::IDLE) do
          on_branch_blocked(sound_bin, mixer_pad)
        end
      else
        # Nothing is streaming, so a blocking probe would never be called.
        destroy_branch(sound_bin, mixer_pad)
      end
    end

    # Releases the pipeline, called on app shutdown.
    def stop
      pipeline.set_state(Gst::State::NULL)
    end

    # Sounds

    def each(&block) = @sounds.each(&block)
    def size = @sounds.length
    def to_a = @sounds.dup

    def append(sound)
      @sounds << sound
      items_changed(@sounds.length - 1, 0, 1)
    end

    def remove(position)
      @sounds.delete_at(position)
      items_changed(position, 1, 0)
    end

    def get_by_name(name) = @sounds.find { |sound| sound.name == name }
    def get_index(name) = @sounds.index { |sound| sound.name == name }
    def get_by_index(index) = @sounds[index]

    # Runs the block with (position, removed, added) whenever the sound list
    # changes. Upstream's Gio.ListModel "items-changed".
    def on_items_changed(&block) = @items_changed_callbacks << block

    # Presets and volumes

    def mute_vol_zero
      @sounds.each do |sound|
        if sound.saved_volume.zero?
          sound.playing = false
        end
      end
    end

    def reset_volumes
      @sounds.each(&:reset_volumes)
      @reset_volumes_callbacks.each(&:call)
    end

    def on_reset_volumes(&block) = @reset_volumes_callbacks << block
    def on_preset_changed(&block) = @preset_changed_callbacks << block

    def next_preset
      if can_next?
        Settings.get.presets.then do |presets|
          Settings.get.active_preset = presets[presets.index(Settings.get.active_preset) + 1]
        end
      end
    end

    def prev_preset
      if can_prev?
        Settings.get.presets.then do |presets|
          Settings.get.active_preset = presets[presets.index(Settings.get.active_preset) - 1]
        end
      end
    end

    def can_next?
      Settings.get.presets.then do |presets|
        presets.length > 1 && presets.index(Settings.get.active_preset) != presets.length - 1
      end
    end

    def can_prev?
      Settings.get.presets.then do |presets|
        presets.length > 1 && presets.index(Settings.get.active_preset).to_i.positive?
      end
    end

    private

      def elements = [mixer, convert, resample, sink_volume, sink]

      def items_changed(position, removed, added)
        @items_changed_callbacks.each { |callback| callback.call(position, removed, added) }
      end

      def link_branch(sound_bin, src_pad, mixer_pad)
        # Shift the branch to where the mixer already is, or it would produce
        # buffers the mixer considers long past and drops.
        src_pad.set_offset(branch_offset)
        src_pad.link(mixer_pad)

        @branches += 1
        sync_pipeline_state
        sound_bin.bin.sync_state_with_parent

        mixer_pad
      end

      def on_branch_blocked(sound_bin, mixer_pad)
        # States cannot be changed from a streaming thread.
        GLib::Idle.add do
          destroy_branch(sound_bin, mixer_pad)
          false
        end

        Gst::PadProbeReturn::REMOVE
      end

      # Destroys a sound branch and removes it from the pipeline.
      def destroy_branch(sound_bin, mixer_pad)
        # Stop the branch before unlinking it, so it does not push into a pad
        # that is already gone.
        sound_bin.bin.set_state(Gst::State::NULL)
        sound_bin.bin.get_static_pad("src")&.unlink(mixer_pad)

        mixer.release_request_pad(mixer_pad)
        pipeline.remove(sound_bin.bin)

        @detaching.delete(sound_bin.bin)
        @branches -= 1
        sync_pipeline_state
      end

      # A branch about to be attached has to be shifted to match the mixer's
      # current position: the mixer works in running time, so a branch joining
      # a pipeline that already advanced would be mixed in the past and
      # dropped.
      def branch_offset
        offset_for_state(pipeline_state).then do |offset|
          if offset == Gst::CLOCK_TIME_NONE
            0
          else
            offset
          end
        end
      end

      def offset_for_state(state)
        case state
        when Gst::State::PLAYING then mixer.current_running_time
        when Gst::State::PAUSED then pipeline.start_time
        else 0
        end
      end

      def pipeline_state = pipeline.get_state(0)[1]

      def sync_pipeline_state
        pipeline.set_state(wanted_state)
      end

      def wanted_state
        if @branches.zero?
          # An audiomixer with no pads never prerolls, and it would leave the
          # next attached branch stuck; keep the pipeline down instead.
          Gst::State::NULL
        elsif playing?
          Gst::State::PLAYING
        else
          Gst::State::PAUSED
        end
      end

      def on_pipeline_error(message)
        unless owner(message.src, @detaching)
          report_error(message)
        end
      end

      def report_error(message)
        message.parse_error.then do |error, debug|
          warn("Error: GStreamer playback failed: #{error.message}\n#{debug}")
        end

        # Every sound shares this pipeline, so a single unreadable file would
        # otherwise take the whole mix down with it.
        sound_of(message.src)&.failed = true

        GLib::Idle.add do
          recover
          false
        end
      end

      # Brings the pipeline back after an error. GStreamer will not resume a
      # pipeline that reported one, so it has to go through NULL and have the
      # remaining sounds attached again.
      def recover
        # The whole pipeline goes down first: tearing the branches down one by
        # one would block on threads the stalled mixer still holds.
        pipeline.set_state(Gst::State::NULL)

        @sounds.each(&:release_now)

        @branches = 0
        @detaching.clear

        @sounds.each do |sound|
          if sound.playing? && sound.saved_volume.positive?
            sound.play_now
          end
        end
      end

      # Finds the sound a pipeline element belongs to, if any.
      def sound_of(element)
        @sounds.to_h { |sound| [sound.player&.bin, sound] }.then do |branches|
          branches.delete(nil)
          owner(element, branches)
        end
      end

      # Walks up from an element to the branch it lives in. `branches` is
      # either a hash of bin => sound, in which case the sound comes back, or a
      # list of bins, in which case the bin does.
      def owner(element, branches)
        found = nil
        current = element

        while current && found.nil?
          if branches.include?(current)
            found = lookup(current, branches)
          end

          current = current.parent
        end

        found
      end

      def lookup(element, branches)
        if branches.is_a?(Hash)
          branches[element]
        else
          element
        end
      end

      # Sets suspension inhibition.
      def inhibit(wanted)
        Gtk::Application.default.then do |app|
          unless app.nil?
            toggle_inhibit(app, wanted)
          end
        end
      end

      def toggle_inhibit(app, wanted)
        if wanted
          unless @cookie.positive?
            @cookie = app.inhibit(nil, Gtk::ApplicationInhibitFlags::SUSPEND, "Playback in progress")
          end
        elsif @cookie.positive?
          app.uninhibit(@cookie)
          @cookie = 0
        end
      end

      def on_settings_inhibition
        if Settings.get.inhibit_suspension
          inhibit(playing?)
        else
          inhibit(false)
        end
      end

      def handle_preset_changed(preset_id)
        @sounds.each(&:preset_changed)
        Preset.new(preset_id).then do |preset|
          @preset_changed_callbacks.each { |callback| callback.call(preset) }
        end
      end
  end
end
