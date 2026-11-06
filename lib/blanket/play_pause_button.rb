# frozen_string_literal: true

require "gtk4"

module Blanket
  # Ported from blanket/widgets/playpause.py.
  #
  # Upstream subclasses Gtk.Button and carries a "playing" GObject property
  # that a notify handler turns into the icon. Ruby-defined GObject
  # properties are not worth the plumbing here — see the note on Preset — so
  # this wraps a Gtk::Button instead and #playing= does directly what the
  # property notify handler did.
  class PlayPauseButton
    def build
      button.tap { self.playing = true }
    end

    def button
      @button ||= Gtk::Button.new.tap do |btn|
        btn.add_css_class("playpause")
        btn.add_css_class("circular")
        btn.add_css_class("suggested-action")
      end
    end

    def playing? = @playing

    def playing=(value)
      @playing = value

      if value
        button.icon_name = "media-playback-pause-symbolic"
      else
        button.icon_name = "media-playback-start-symbolic"
      end
    end
  end
end
