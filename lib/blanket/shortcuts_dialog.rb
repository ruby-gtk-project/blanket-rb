# frozen_string_literal: true

require "adwaita"

module Blanket
  # Ported from data/resources/shortcuts.blp.
  #
  # One section, six items. Upstream's items carry action names and let
  # Adw.ShortcutsItem look the accelerator up from the application; the items
  # here carry the accelerator directly, because that is the form the Ruby
  # bindings take positionally and it keeps the dialog readable without an
  # application instance. The accelerators are the ones main.py binds.
  class ShortcutsDialog
    SECTIONS = {
      "General" => [
        ["Play/Pause Sounds", "<Control>m"],
        ["Add Custom Sound", "<Control>o"],
        ["Close Window", "<Control>w"],
        ["Preferences", "<Control>comma"],
        ["Keyboard Shortcuts", "<Control>question"],
        ["Quit", "<Control>q"],
      ],
    }.freeze

    def build
      dialog.tap do |dlg|
        SECTIONS.each do |title, items|
          dlg.add(section(title, items))
        end
      end
    end

    def present(parent) = build.present(parent)

    def dialog = @dialog ||= Adwaita::ShortcutsDialog.new.tap { |dlg| dlg.title = "Keyboard Shortcuts" }

    private

      def section(title, items)
        Adwaita::ShortcutsSection.new.tap do |group|
          group.title = title
          items.each { |label, accelerator| group.add(item(label, accelerator)) }
        end
      end

      # Positional, not keyword, arguments — even though the error a
      # no-argument new raises advertises the signatures as
      # "title: utf8, accelerator: utf8".
      def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
  end
end
