# frozen_string_literal: true

require "gio2"
require_relative "define"
require_relative "i18n"
require_relative "main_player"
require_relative "settings"

module Blanket
  # Ported from blanket/mpris.py.
  #
  # Exposes the app to the desktop's media controls over the
  # org.mpris.MediaPlayer2 D-Bus interfaces. Blanket has no track to seek or
  # skip within, so CanSeek is always false and Position is always zero; the
  # "track" that changes is the active preset, and Next/Previous move
  # between presets rather than between songs.
  #
  # Upstream's Server base class walks `Gio::DBusNodeInfo#interfaces` to
  # register whatever the class docstring declares; ShellSearchProvider's
  # comment on this port notes that #interfaces returns unusable strings in
  # these bindings, so each interface here is looked up by name and
  # registered on its own, all four sharing the one method-call dispatcher.
  class Mpris
    include GetText

    BUS_NAME = "org.mpris.MediaPlayer2.Blanket"
    OBJECT_PATH = "/org/mpris/MediaPlayer2"
    INTROSPECTABLE_IFACE = "org.freedesktop.DBus.Introspectable"
    PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"
    MEDIA_PLAYER_IFACE = "org.mpris.MediaPlayer2"
    PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"

    NODE_XML = <<~XML
      <node>
        <interface name="org.freedesktop.DBus.Introspectable">
          <method name="Introspect">
            <arg name="data" direction="out" type="s"/>
          </method>
        </interface>
        <interface name="org.freedesktop.DBus.Properties">
          <method name="Get">
            <arg name="interface" direction="in" type="s"/>
            <arg name="property" direction="in" type="s"/>
            <arg name="value" direction="out" type="v"/>
          </method>
          <method name="Set">
            <arg name="interface_name" direction="in" type="s"/>
            <arg name="property_name" direction="in" type="s"/>
            <arg name="value" direction="in" type="v"/>
          </method>
          <method name="GetAll">
            <arg name="interface" direction="in" type="s"/>
            <arg name="properties" direction="out" type="a{sv}"/>
          </method>
        </interface>
        <interface name="org.mpris.MediaPlayer2">
          <method name="Raise"/>
          <method name="Quit"/>
          <property name="CanQuit" type="b" access="read"/>
          <property name="CanRaise" type="b" access="read"/>
          <property name="HasTrackList" type="b" access="read"/>
          <property name="Identity" type="s" access="read"/>
          <property name="DesktopEntry" type="s" access="read"/>
          <property name="SupportedUriSchemes" type="as" access="read"/>
          <property name="SupportedMimeTypes" type="as" access="read"/>
        </interface>
        <interface name="org.mpris.MediaPlayer2.Player">
          <method name="Next"/>
          <method name="Previous"/>
          <method name="PlayPause"/>
          <method name="Play"/>
          <method name="Pause"/>
          <method name="Stop"/>
          <signal name="Seeked">
            <arg name="Position" type="x"/>
          </signal>
          <property name="PlaybackStatus" type="s" access="read"/>
          <property name="Metadata" type="a{sv}" access="read"/>
          <property name="Position" type="x" access="read"/>
          <property name="Rate" type="d" access="readwrite"/>
          <property name="MinimumRate" type="d" access="read"/>
          <property name="MaximumRate" type="d" access="read"/>
          <property name="Volume" type="d" access="readwrite"/>
          <property name="CanSeek" type="b" access="read"/>
          <property name="CanGoNext" type="b" access="read"/>
          <property name="CanGoPrevious" type="b" access="read"/>
          <property name="CanPlay" type="b" access="read"/>
          <property name="CanPause" type="b" access="read"/>
          <property name="CanControl" type="b" access="read"/>
        </interface>
      </node>
    XML

    INTERFACES = [INTROSPECTABLE_IFACE, PROPERTIES_IFACE, MEDIA_PLAYER_IFACE, PLAYER_IFACE].freeze

    # `app` answers Raise and Quit — the application, not the window.
    def initialize(app)
      @app = app
      @track_id = 10_000_000 + rand(80_000_000)

      MainPlayer.get.on_preset_changed { |preset| on_preset_changed(preset) }
      MainPlayer.get.on_playing_changed { |_playing| on_playing_changed }
      MainPlayer.get.on_volume_changed { |volume| on_volume_changed(volume) }
    end

    # Registers every interface on the session bus and owns the well-known
    # name. Separate from #initialize so a drive script can build the
    # server, talk to it over the bus, and keep its own main loop.
    def build
      @build ||= bus.tap do |connection|
        INTERFACES.each do |name|
          connection.register_object(OBJECT_PATH, interface_info(name)) do |*closure_args|
            handle_method_call(*closure_args.last(4))
          end
        end

        Gio.bus_own_name_on_connection(connection, BUS_NAME, Gio::BusNameOwnerFlags::NONE)
      end
    end

    def bus = @bus ||= Gio.bus_get_sync(Gio::BusType::SESSION)

    def interface_info(name) = Gio::DBusNodeInfo.new(NODE_XML).lookup_interface(name)

    private

      def handle_method_call(interface_name, method_name, parameters, invocation)
        case [interface_name, method_name]
        when [INTROSPECTABLE_IFACE, "Introspect"]
          invocation.return_value(GLib::Variant.parse("(#{quote(NODE_XML)},)", "(s)"))
        when [PROPERTIES_IFACE, "Get"]
          handle_get(parameters, invocation)
        when [PROPERTIES_IFACE, "Set"]
          handle_set(parameters, invocation)
        when [PROPERTIES_IFACE, "GetAll"]
          handle_get_all(parameters, invocation)
        when [MEDIA_PLAYER_IFACE, "Raise"]
          @app.on_raise
          invocation.return_value(nil)
        when [MEDIA_PLAYER_IFACE, "Quit"]
          @app.on_quit
          invocation.return_value(nil)
        when [PLAYER_IFACE, "Next"]
          MainPlayer.get.next_preset
          invocation.return_value(nil)
        when [PLAYER_IFACE, "Previous"]
          MainPlayer.get.prev_preset
          invocation.return_value(nil)
        when [PLAYER_IFACE, "PlayPause"]
          @app.on_playpause
          invocation.return_value(nil)
        when [PLAYER_IFACE, "Play"]
          @app.on_play
          invocation.return_value(nil)
        when [PLAYER_IFACE, "Pause"], [PLAYER_IFACE, "Stop"]
          @app.on_pause
          invocation.return_value(nil)
        else
          invocation.return_dbus_error("#{interface_name}.UnknownMethod", "Unknown method #{method_name}")
        end
      rescue StandardError => e
        invocation.return_dbus_error("#{interface_name}.Error", e.message)
      end

      # `parameters` arrives already unwrapped to a Ruby Array of its
      # tuple's own already-unwrapped values — the same auto-conversion
      # the "change-state" and "activate" signal handlers get, documented
      # on Application#on_background — not the GLib::Variant that
      # `parameters.get_child_value(i)` would read from.
      def handle_get(parameters, invocation)
        _interface, name = parameters
        invocation.return_value(GLib::Variant.parse("(#{property_text(name)},)", "(v)"))
      end

      def handle_set(parameters, invocation)
        _interface, name, value = parameters

        if name == "Volume"
          MainPlayer.get.volume = value
        end

        invocation.return_value(nil)
      end

      def handle_get_all(parameters, invocation)
        interface, = parameters
        names = property_names(interface)
        body = names.map { |name| "#{quote(name)}: #{property_text(name)}" }.join(", ")
        invocation.return_value(GLib::Variant.parse("({#{body}},)", "(a{sv})"))
      end

      def property_names(interface)
        case interface
        when MEDIA_PLAYER_IFACE
          %w[CanQuit CanRaise HasTrackList Identity DesktopEntry SupportedUriSchemes SupportedMimeTypes]
        when PLAYER_IFACE
          %w[PlaybackStatus Metadata Position Rate MinimumRate MaximumRate Volume CanSeek CanGoNext
             CanGoPrevious CanPlay CanPause CanControl
]
        else
          []
        end
      end

      # The GVariant text format fragment for a property's *boxed* value —
      # what belongs inside the angle brackets of a variant, or the angle
      # brackets themselves for the few whose type needs them disambiguated.
      def property_text(name)
        case name
        when "CanQuit", "CanRaise", "CanControl", "CanPlay", "CanPause"
          "<true>"
        when "HasTrackList"
          "<false>"
        when "SupportedUriSchemes", "SupportedMimeTypes"
          "<@as []>"
        when "CanGoNext"
          "<#{MainPlayer.get.can_next?}>"
        when "CanGoPrevious"
          "<#{MainPlayer.get.can_prev?}>"
        when "Identity"
          "<#{quote(_("Blanket"))}>"
        when "DesktopEntry"
          "<#{quote(Define::APP_ID)}>"
        when "PlaybackStatus"
          "<#{quote(playback_status)}>"
        when "Metadata"
          "<#{metadata_text}>"
        when "Volume"
          "<#{MainPlayer.get.volume}>"
        when "Position"
          "<@x 0>"
        when "Rate", "MinimumRate", "MaximumRate"
          "<1.0>"
        when "CanSeek"
          "<false>"
        else
          raise ArgumentError, "No such property '#{name}'"
        end
      end

      def metadata_text
        fields = {
          "mpris:trackid" => "<@o #{quote("#{Define::RES_PATH}/Track/#{@track_id}")}>",
          "xesam:title"   => "<#{quote(Settings.get.active_preset_name)}>",
          "xesam:album"   => "<#{quote(_("Listen to different sounds"))}>",
          "xesam:artist"  => "<@as [#{quote(_("Blanket"))}]>",
        }
        "@a{sv} {#{fields.map { |key, value| "#{quote(key)}: #{value}" }.join(", ")}}"
      end

      def playback_status
        if MainPlayer.get.playing?
          "Playing"
        else
          "Paused"
        end
      end

      def properties_changed(interface_name, changed_properties)
        body = changed_properties.map { |name| "#{quote(name)}: #{property_text(name)}" }.join(", ")

        bus.emit_signal(
          nil,
          OBJECT_PATH,
          PROPERTIES_IFACE,
          "PropertiesChanged",
          GLib::Variant.parse("(#{quote(interface_name)}, {#{body}}, @as [])", "(sa{sv}as)"),
        )
      end

      def on_preset_changed(_preset)
        properties_changed(PLAYER_IFACE, %w[Metadata CanGoNext CanGoPrevious])
      end

      def on_playing_changed
        properties_changed(PLAYER_IFACE, %w[PlaybackStatus])
      end

      def on_volume_changed(_volume)
        properties_changed(PLAYER_IFACE, %w[Volume])
      end

      ESCAPES = {"\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n"}.freeze

      def quote(value) = %("#{value.to_s.gsub(/[\\"\n]/) { |char| ESCAPES.fetch(char) }}")
  end
end
