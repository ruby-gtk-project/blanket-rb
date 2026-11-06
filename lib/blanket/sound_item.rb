# frozen_string_literal: true

require "gtk4"
require_relative "sound_context_menu"

module Blanket
  # Ported from blanket/widgets/sound_item.py and
  # data/resources/sound-item.blp.
  #
  # One tile of the sounds grid: an icon, a title and a volume slider that
  # only appears once the tile has a Sound. A right-click opens
  # SoundContextMenu at the pointer. Upstream carries GObject properties the
  # window's model binds to; here the window calls #sound= directly and this
  # refreshes itself from the blocks Sound gives to #on_changed.
  class SoundItem
    # `index` is the sound's position in MainPlayer, which the right-click
    # menu's Rename/Remove actions target. It is a block rather than a plain
    # value because custom sounds can be removed, which shifts every later
    # index.
    def initialize(index:)
      @index = index
      @sound = nil
      @menu = nil
    end

    attr_reader :sound

    def build
      child.tap do |item|
        item.child = box

        box.tap do |b|
          b.append(icon)
          b.append(label)
          b.append(scale)
        end

        click.tap do |gesture|
          gesture.button = 3
          gesture.signal_connect("pressed") { |_g, _n, x, y| on_secondary_click(x, y) }
        end
        item.add_controller(click)
      end
    end

    # Fills the tile with a real Sound, wiring the scale and the live
    # refresh. A nil sound leaves the tile as the "Add…" placeholder the
    # window sets title and icon_name on directly.
    def sound=(value)
      @sound = value

      unless @sound.nil?
        scale.visible = true
        @sound.on_changed { refresh }
        refresh
      end
    end

    def title=(value)
      label.label = value
    end

    def icon_name=(value)
      icon.icon_name = value
    end

    def child
      @child ||= Gtk::FlowBoxChild.new.tap do |c|
        c.width_request = 100
        c.add_css_class("sound-item")
      end
    end

    def box = @box ||= Gtk::Box.new(:vertical, 6)

    def icon
      @icon ||= Gtk::Image.new.tap do |i|
        i.halign = :center
        i.pixel_size = 64
      end
    end

    def label
      @label ||= Gtk::Label.new.tap do |l|
        l.ellipsize = :end
        l.lines = 2
        l.justify = :center
        l.max_width_chars = 10
        l.height_request = 40
        l.wrap = true
      end
    end

    def scale
      @scale ||= Gtk::Scale.new(:horizontal, adjustment).tap do |s|
        s.hexpand = true
        s.draw_value = false
        s.visible = false
      end
    end

    def adjustment
      @adjustment ||= Gtk::Adjustment.new(
        0,
        0,
        1,
        0.01,
        0.01,
        0,
      ).tap do |adj|
        adj.signal_connect("value-changed") { on_volume_changed }
      end
    end

    def click = @click ||= Gtk::GestureClick.new

    private

      def on_volume_changed
        unless @sound.nil? || @syncing_volume
          @sound.saved_volume = adjustment.value
        end
      end

      # Mirrors _playing_changed/_failed_changed/the icon/title/error
      # bindings: everything the tile shows follows the sound, in one pass.
      #
      # Setting the adjustment's value fires its own "value-changed" signal
      # even on a programmatic set, which #on_volume_changed would otherwise
      # write straight back into the sound — re-entering Sound#changed,
      # which calls back here. @syncing_volume breaks that cycle.
      def refresh
        label.label = @sound.title
        icon.icon_name = @sound.icon_name
        child.tooltip_text = @sound.error_message

        @syncing_volume = true
        adjustment.value = @sound.saved_volume
        @syncing_volume = false

        scale.sensitive = @sound.playing?

        if @sound.playing?
          icon.add_css_class("accent")
        else
          icon.remove_css_class("accent")
        end

        if @sound.failed?
          child.add_css_class("error")
        else
          child.remove_css_class("error")
        end
      end

      def on_secondary_click(x, y)
        unless @sound.nil?
          context_menu(x, y).popup
        end
      end

      # Rebuilt on every click rather than memoized: this tile outlives any
      # one right-click (it is cached and reused across Window's list
      # rebuilds), while the Rename/Remove targets bake in the sound's
      # index at menu-build time, and that index shifts whenever another
      # custom sound is removed.
      def context_menu(x, y)
        @menu&.unparent

        SoundContextMenu.new(@sound, @index.call).build.tap do |menu|
          menu.set_parent(child)
          menu.pointing_to = Gdk::Rectangle.new(
            x.to_i,
            y.to_i,
            1,
            1,
          )
          @menu = menu
        end
      end
  end
end
