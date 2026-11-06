# frozen_string_literal: true

require "gtk4"

module Blanket
  # Ported from blanket/widgets/sound_context_menu.py and
  # data/resources/sound-context-menu.blp.
  #
  # The right-click menu on a sound tile: a volume slider always, and for a
  # custom sound a Rename/Remove section targeting the app actions that take
  # the sound's index. The slider is bound to the sound's saved volume only
  # while the popover is open, and unbound when it closes, matching
  # upstream's do_closed.
  class SoundContextMenu
    def initialize(sound, index)
      @sound = sound
      @index = index
    end

    def build
      popover.tap do |pop|
        pop.menu_model = menu_model
        pop.add_child(scale, "volume")
        pop.signal_connect("show") { on_opened }
        pop.signal_connect("closed") { on_closed }
      end
    end

    def popover
      @popover ||= Gtk::PopoverMenu.new.tap do |pop|
        pop.has_arrow = false
        pop.position = :right
        pop.valign = :start
        pop.width_request = 200
      end
    end

    def menu_model
      @menu_model ||= Gio::Menu.new.tap do |menu|
        menu.append_section(nil, volume_section)

        if @sound.custom
          menu.append_section(nil, custom_section)
        end
      end
    end

    def volume_section
      @volume_section ||= Gio::Menu.new.tap do |section|
        section.append_item(Gio::MenuItem.new.tap { |item| item.set_attribute_value("custom", GLib::Variant.new("volume")) })
      end
    end

    def custom_section
      @custom_section ||= Gio::Menu.new.tap do |section|
        section.append_item(
          Gio::MenuItem.new("Rename", nil).tap do |item|
            item.set_action_and_target_value("app.rename-sound", GLib::Variant.new(@index, "u"))
          end,
        )
        section.append_item(
          Gio::MenuItem.new("Remove", nil).tap do |item|
            item.set_action_and_target_value("app.remove-sound", GLib::Variant.new(@index, "u"))
          end,
        )
      end
    end

    def scale
      @scale ||= Gtk::Scale.new(:horizontal, adjustment).tap do |s|
        s.hexpand = true
        s.draw_value = false
      end
    end

    def adjustment = @adjustment ||= Gtk::Adjustment.new(
      0,
      0,
      1,
      0.01,
      0.01,
      0,
    )

    private

      def on_opened
        adjustment.value = @sound.saved_volume
        @handler_id = adjustment.signal_connect("value-changed") { @sound.saved_volume = adjustment.value }
        scale.sensitive = !@sound.failed?
      end

      def on_closed
        unless @handler_id.nil?
          adjustment.signal_handler_disconnect(@handler_id)
          @handler_id = nil
        end
      end
  end
end
