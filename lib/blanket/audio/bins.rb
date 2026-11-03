# frozen_string_literal: true

require "gstreamer"

module Blanket
  module Audio
    # Ported from blanket/audio/bins.py.
    #
    # Upstream subclasses Gst.Bin. A Ruby subclass of a GStreamer type is not
    # registered as that type with GObject — `GLib::Object.type_register` does
    # not carry interfaces or let GStreamer treat the result as a real bin — so
    # each of these owns a Gst::Bin instead and hands it out as #bin.
    # MainPlayer adds that bin to the shared pipeline.
    class SoundBin
      # Every branch has to reach the mixer in the same format: audiomixer does
      # not convert, so a sound recorded at another rate is resampled first,
      # and mixing at the rate the sounds already are in keeps the resamplers
      # idle.
      CAPS = "audio/x-raw,format=F32LE,rate=44100,channels=2,layout=interleaved"

      def initialize(name)
        @name = name
      end

      attr_reader :name

      # Assembles the branch and returns its Gst::Bin.
      def build
        if complete?
          assemble
        else
          warn("Error: could not create the GStreamer elements for a sound")
          bin
        end
      end

      def bin = @bin ||= Gst::Bin.new(name)

      def volume = volume_element.get_property("volume")

      def volume=(value)
        volume_element.set_property("volume", value)
      end

      def convert = @convert ||= Gst::ElementFactory.make("audioconvert", nil)
      def resample = @resample ||= Gst::ElementFactory.make("audioresample", nil)
      def volume_element = @volume_element ||= Gst::ElementFactory.make("volume", nil)

      def caps_filter
        @caps_filter ||= Gst::ElementFactory.make("capsfilter", nil).tap do |element|
          element.set_property("caps", Gst::Caps.from_string(CAPS))
        end
      end

      private

        # Everything the branch puts in its bin. Subclasses prepend their own
        # source element.
        def elements = [convert, resample, caps_filter, volume_element]

        # The elements linked head to tail. A source whose pads only appear
        # once it has data — uridecodebin — is left out and linked later.
        def chain = [convert, resample, caps_filter, volume_element]

        def complete? = elements.none?(&:nil?)

        def assemble
          bin.tap do |container|
            elements.each { |element| container.add(element) }
            chain.each_cons(2) { |source, target| source.link(target) }
            container.add_pad(Gst::GhostPad.new("src", volume_element.get_static_pad("src")))
            wire
          end
        end

        # Hook for the branches that need signals or pad probes of their own.
        def wire = nil
    end

    # Ported from bins.py's LoopBin: a decoded file played back forever.
    #
    # The branch has no sink of its own, so the pipeline never posts
    # SEGMENT_DONE for it; the matching event is caught as it leaves the branch
    # instead, and answered with a fresh segment seek.
    class LoopBin < SoundBin
      # A sound whose duration is not known yet cannot be looped, so wait for
      # it rather than seeking into an empty segment.
      LOOP_RETRY_INTERVAL = 200
      LOOP_RETRIES = 25

      def initialize(name, uri)
        super(name)
        @uri = uri
        @looping = false
      end

      attr_reader :uri

      def decoder
        @decoder ||= Gst::ElementFactory.make("uridecodebin", nil).tap do |element|
          element.set_property("uri", uri)
        end
      end

      private

        def elements = [decoder, convert, resample, caps_filter, volume_element]

        def wire
          decoder.signal_connect("pad-added") { |_decoder, pad| on_pad_added(pad) }
        end

        def on_pad_added(pad)
          convert.get_static_pad("sink").then do |sink_pad|
            unless sink_pad.nil? || sink_pad.linked?
              pad.link(sink_pad)
            end
          end

          bin.get_static_pad("src").then do |src_pad|
            unless src_pad.nil?
              # Seeking before the caps are negotiated fails, so wait for data.
              src_pad.add_probe(Gst::PadProbeType::BUFFER) { on_first_buffer }
              src_pad.add_probe(Gst::PadProbeType::EVENT_DOWNSTREAM) { |_pad, info| on_branch_event(info) }
            end
          end
        end

        def on_first_buffer
          GLib::Idle.add do
            start_loop(0)
            false
          end

          Gst::PadProbeReturn::REMOVE
        end

        def start_loop(attempt)
          unless @looping
            if seek(flush: true)
              @looping = true
            else
              retry_loop(attempt) { |next_attempt| start_loop(next_attempt) }
            end
          end
        end

        def restart_loop(attempt)
          unless seek(flush: false)
            retry_loop(attempt) { |next_attempt| restart_loop(next_attempt) }
          end
        end

        # Tries again later when the duration is not known yet. Retrying from
        # the idle callback itself would only spin the main loop, and a sound
        # whose duration never resolves would spin it forever.
        def retry_loop(attempt, &block)
          if attempt >= LOOP_RETRIES
            warn("Error: could not loop #{uri}, its duration is unknown")
          else
            GLib::Timeout.add(LOOP_RETRY_INTERVAL) do
              block.call(attempt + 1)
              false
            end
          end
        end

        def on_branch_event(info)
          info.event.then do |event|
            if event.nil?
              Gst::PadProbeReturn::OK
            else
              answer_branch_event(event.type)
            end
          end
        end

        def answer_branch_event(type)
          case type
          when Gst::EventType::SEGMENT_DONE
            GLib::Idle.add do
              restart_loop(0)
              false
            end
            Gst::PadProbeReturn::DROP
          when Gst::EventType::EOS
            # Letting it through would end the whole pipeline.
            Gst::PadProbeReturn::DROP
          else
            Gst::PadProbeReturn::OK
          end
        end

        # The segment has to be given an explicit end: seeking before the
        # duration is known would leave an empty one, looping on itself.
        def seek(flush:)
          bin.query_duration(Gst::Format::TIME).then do |known, duration|
            if !known || duration <= 0
              false
            else
              bin.seek(
                1.0,
                Gst::Format::TIME,
                seek_flags(flush),
                Gst::SeekType::SET,
                0,
                Gst::SeekType::SET,
                duration,
              )
            end
          end
        end

        def seek_flags(flush)
          if flush
            Gst::SeekFlags::SEGMENT | Gst::SeekFlags::FLUSH
          else
            Gst::SeekFlags::SEGMENT
          end
        end
    end

    # Ported from bins.py's NoiseBin: noise generated in real time, so there is
    # nothing to decode and nothing to loop.
    class NoiseBin < SoundBin
      # audiotestsrc's wave names are the sound names Define carries:
      # "pink-noise" and "white-noise".
      def noise
        @noise ||= Gst::ElementFactory.make("audiotestsrc", nil).tap do |element|
          element.set_property("freq", 100.0)
          element.set_property("wave", name)
        end
      end

      private

        def elements = [noise, convert, resample, caps_filter, volume_element]
        def chain = [noise, convert, resample, caps_filter, volume_element]
    end
  end
end
