# frozen_string_literal: true

require "gtk4"

module Blanket
  # Ported from blanket/widgets/volume_row.py and
  # data/resources/volume-row.blp.
  #
  # One row of the volume popover's list: a caption with the sound's title
  # and a slider for its volume. Upstream binds both to the row's own "title"
  # and "volume" GObject properties bidirectionally; here the window that
  # creates a row wires its slider straight to the Sound it stands for, so
  # #title= and #volume= are the only surface this needs.
  class VolumeRow
    def build
      row.tap do |r|
        r.child = box

        box.tap do |b|
          b.append(title_label)
          b.append(scale)
        end
      end
    end

    def row
      @row ||= Gtk::ListBoxRow.new.tap do |r|
        r.selectable = false
        r.add_css_class("volume-row")
      end
    end

    def box = @box ||= Gtk::Box.new(:vertical, 0)

    def title_label
      @title_label ||= Gtk::Label.new.tap do |label|
        label.ellipsize = :end
        label.xalign = 0
        label.add_css_class("caption-heading")
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

    def title=(value)
      title_label.label = value
    end

    def volume=(value)
      adjustment.value = value
    end

    def volume = adjustment.value

    def on_volume_changed(&block)
      adjustment.signal_connect("value-changed") { block.call(adjustment.value) }
    end
  end
end
