# frozen_string_literal: true

# Drives the application object: its GActions, accelerators, MPRIS surface
# and shutdown/close-request handling — everything in application.rb that
# the window-focused drivers (drive_window.rb, drive_presets.rb) never
# reach because it lives above the window, not inside it.
#
# The settings live in the memory GSettings backend, so a run neither reads
# nor writes the real configuration.

ENV["GSETTINGS_BACKEND"] = "memory"

require "tmpdir"
ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "blanket"
require_relative "gtk_driver"

def window(app) = app.send(:blanket_window)

# MPRIS registers its four interfaces as D-Bus object handlers, but calling
# through a real client (DBusConnection#call_sync) from the same process
# deadlocks: the reply can only be dispatched once the main loop is free,
# and call_sync blocks that very loop waiting on it. A real MPRIS client
# (gnome-shell, playerctl) lives in another process and has no such
# problem; here the dispatcher is exercised directly, the way the skill's
# "call the handler the way the widget would" rule means for a GDBus
# method table rather than a widget signal.
FakeInvocation = Struct.new(:value, :error) do
  def return_value(v) = self.value = v
  def return_dbus_error(name, msg) = self.error = [name, msg]
end

def call_mpris(mpris, iface, method, params = [])
  FakeInvocation.new.tap do |inv|
    mpris.send(:handle_method_call, iface, method, params, inv)
  end
end

MEDIA_PLAYER_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"

GtkDriver.drive(Blanket::Application.new, shots: "tmp/shots", interval: 900) do |d, app|
  d.window { window(app).window }

  d.step("the window builds") do
    @mpris = app.send(:mpris)

    d.check("MPRIS registered its object on the session bus") { !@mpris.instance_variable_get(:@build).nil? }
  end

  d.step("MPRIS introspection answers") do
    inv = call_mpris(@mpris, "org.freedesktop.DBus.Introspectable", "Introspect")

    d.check("the node XML comes back") { inv.value.to_s.include?("org.mpris.MediaPlayer2.Player") }
  end

  d.step("MPRIS reports CanGoNext/CanGoPrevious against the real preset count") do
    inv_next = call_mpris(@mpris, PROPERTIES_IFACE, "Get", [PLAYER_IFACE, "CanGoNext"])
    inv_prev = call_mpris(@mpris, PROPERTIES_IFACE, "Get", [PLAYER_IFACE, "CanGoPrevious"])

    d.check("CanGoNext matches MainPlayer") { inv_next.value.value.first == Blanket::MainPlayer.get.can_next? }
    d.check("CanGoPrevious matches MainPlayer") { inv_prev.value.value.first == Blanket::MainPlayer.get.can_prev? }
  end

  d.step("MPRIS Raise presents the window") do
    window(app).window.visible = false
    call_mpris(@mpris, MEDIA_PLAYER_IFACE, "Raise")

    d.check("the window is visible again") { window(app).window.visible? }
  end

  d.step("MPRIS PlayPause toggles playback") do
    @was_playing = Blanket::MainPlayer.get.playing?
    call_mpris(@mpris, PLAYER_IFACE, "PlayPause")

    d.check("playback flipped") { Blanket::MainPlayer.get.playing? == !@was_playing }
  end

  d.step("the PlaybackStatus property follows") do
    inv = call_mpris(@mpris, PROPERTIES_IFACE, "Get", [PLAYER_IFACE, "PlaybackStatus"])
    expected = Blanket::MainPlayer.get.playing? ? "Playing" : "Paused"

    d.check("PlaybackStatus matches") { inv.value.value.first == expected }
  end

  d.step("MPRIS Pause and Play drive playback directly") do
    call_mpris(@mpris, PLAYER_IFACE, "Pause")

    d.check("paused") { !Blanket::MainPlayer.get.playing? }

    call_mpris(@mpris, PLAYER_IFACE, "Play")

    d.check("playing") { Blanket::MainPlayer.get.playing? }
  end

  # a{sv} (Metadata's own type, nested inside the (v) the Get call wraps it
  # in) has no Ruby conversion in these bindings yet (GVariant({sv}) ->
  # Ruby raises NotImplementedError) — a genuine binding gap, not a port
  # bug. #to_s renders the GVariant text format instead, which needs no
  # such conversion and still proves the handler built real metadata.
  d.step("MPRIS Metadata reports the active preset's name") do
    inv = call_mpris(@mpris, PROPERTIES_IFACE, "Get", [PLAYER_IFACE, "Metadata"])
    text = inv.value.to_s

    d.check("xesam:title is the active preset") { text.include?(Blanket::Settings.get.active_preset_name) }
  end

  d.step("MPRIS Next/Previous move between presets") do
    Blanket::Settings.get.add_preset("Evening")
    @before = Blanket::Settings.get.active_preset_name
    call_mpris(@mpris, PLAYER_IFACE, "Next")

    d.check("the active preset changed") { Blanket::Settings.get.active_preset_name != @before }

    call_mpris(@mpris, PLAYER_IFACE, "Previous")

    d.check("and came back") { Blanket::Settings.get.active_preset_name == @before }
  end

  d.step("an unknown MPRIS method returns a DBus error, not a crash") do
    inv = call_mpris(@mpris, PLAYER_IFACE, "Teleport")

    d.check("an error came back") { inv.error&.first == "#{PLAYER_IFACE}.UnknownMethod" }
  end

  d.step("app.background-playback toggles hide-on-close") do
    @app_obj = app.send(:app)
    @app_obj.change_action_state("background-playback", GLib::Variant.new(true))

    d.check("the window now hides instead of closing") { window(app).window.hide_on_close? }
    d.check("the setting followed") { Blanket::Settings.get.background == true }
  end

  d.step("app.reset-volumes resets every sound") do
    noise = Blanket::MainPlayer.get.get_by_name("pink-noise")
    noise.saved_volume = 0.3
    @app_obj.activate_action("reset-volumes", nil)

    d.check("the volume went back to zero") { noise.saved_volume == 0.0 }
    d.check("and playback stopped") { !noise.playing? }
  end

  d.step("app.add-preset opens the preset dialog") do
    @app_obj.activate_action("add-preset", nil)

    d.check("a dialog is showing") { !window(app).window.visible_dialog.nil? }
    window(app).window.visible_dialog.close
  end

  d.step("app.rename-sound opens the rename dialog for a custom sound") do
    custom = Blanket::Sound.new("waterfall", uri: "file:///tmp/waterfall.ogg", custom: true)
    Blanket::MainPlayer.get.append(custom)
    index = Blanket::MainPlayer.get.get_index("waterfall")
    @app_obj.activate_action("rename-sound", GLib::Variant.new(index, "u"))

    d.check("a dialog is showing") { !window(app).window.visible_dialog.nil? }
    window(app).window.visible_dialog.close
  end

  d.step("app.remove-sound removes a custom sound") do
    index = Blanket::MainPlayer.get.get_index("waterfall")
    before = Blanket::MainPlayer.get.size
    @app_obj.activate_action("remove-sound", GLib::Variant.new(index, "u"))

    d.check("the sound is gone") { Blanket::MainPlayer.get.get_by_name("waterfall").nil? }
    d.check("the player shrank by one") { Blanket::MainPlayer.get.size == before - 1 }
  end

  d.step("the accelerators are wired to the right action names") do
    accels = @app_obj.get_accels_for_action("app.quit")

    d.check("Ctrl+Q quits") { accels.include?("<Control>q") }
    d.check("Ctrl+W closes the window") { @app_obj.get_accels_for_action("win.close").include?("<Control>w") }
    d.check("Ctrl+? opens shortcuts") { @app_obj.get_accels_for_action("app.shortcuts").include?("<Control>question") }
  end

  d.step("app.quit ends the application") do
    @app_obj.activate_action("quit", nil)
  end
end
