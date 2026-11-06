# frozen_string_literal: true

module Blanket
  # Ported from blanket/utils.py.
  #
  # Upstream is a GObject implementing Gio.ListModel that joins one dummy
  # object after the wrapped model's own items, so FlowBox.bind_model calls
  # back for every tile including a trailing "Add…" one, and re-renders only
  # the positions "items-changed" reports as changed.
  #
  # A Ruby class cannot implement GListModel for the reason MainPlayer's
  # comment gives, so this wraps MainPlayer's own each/size interface instead
  # and forwards its callback-based #on_items_changed; Window rebuilds its
  # FlowBox tiles directly from #each rather than through FlowBox.bind_model.
  class DummyItemModel
    def initialize(model, dummy)
      @model = model
      @dummy = dummy
    end

    def size = @model.size + 1

    def get_item(position)
      if position == @model.size
        @dummy
      else
        @model.get_by_index(position)
      end
    end

    def each(&block)
      @model.each(&block)
      block.call(@dummy)
    end

    def on_items_changed(&block) = @model.on_items_changed(&block)
  end
end
