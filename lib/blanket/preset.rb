# frozen_string_literal: true

require_relative "settings"

module Blanket
  # Ported from blanket/preset.py.
  #
  # Upstream is a GObject carrying "name" and "active" properties: the name is
  # bound to the preset's own GSettings key, and the active flag follows the
  # app's active-preset key. Defining GObject properties on a Ruby class is not
  # worth the plumbing for two values, so this is a plain object that reads
  # both through Settings and calls the blocks given to #on_changed when
  # either moves — which is what the property bindings were for.
  class Preset
    attr_reader :id

    def initialize(preset_id)
      @id = preset_id
      @callbacks = []

      Settings.get.on_changed("active-preset") { changed }
      preset_settings.signal_connect("changed::visible-name") { |_s, _k| changed }
    end

    def name = Settings.get.get_preset_name(id)

    def name=(value)
      Settings.get.set_preset_name(id, value)
    end

    # Whether this preset's volumes are the ones in effect.
    def active? = Settings.get.active_preset == id

    # Makes this preset the active one.
    def activate
      unless active?
        Settings.get.active_preset = id
      end
    end

    # The preset shipped with the schema can be neither renamed nor removed.
    def custom? = id != Settings.get.default_preset

    # Removes the preset and returns the index it occupied, or nil when it is
    # the default preset and so cannot be removed.
    def remove
      if custom?
        Settings.get.remove_preset(id)
      end
    end

    # Runs the block whenever this preset's name or active state changes.
    def on_changed(&block) = @callbacks << block

    private

      def preset_settings = Settings.get.get_preset_settings(id)

      def changed = @callbacks.each(&:call)
  end
end
