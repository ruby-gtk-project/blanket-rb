# frozen_string_literal: true

require "adwaita"
require_relative "define"
require_relative "i18n"

module Blanket
  # Ported from data/resources/about.blp and main.py's on_about.
  #
  # Upstream builds the dialog from a .ui file and then fills in the version,
  # the icon, the developers, the designers, the source-code link and the two
  # credit sections in code. There is no .ui file here, so all of it is set in
  # one place.
  class AboutDialog
    include GetText

    def build
      dialog.tap do |dlg|
        dlg.add_link(_("Source Code"), "https://github.com/rafaelmardojai/blanket")
        dlg.add_credit_section(_("Sounds by"), Define.credits_list(Define::SOUND_ARTISTS))
        dlg.add_credit_section(_("Sounds edited by"), Define.credits_list(Define::SOUND_EDITORS))
      end
    end

    def present(parent) = build.present(parent)

    def dialog
      @dialog ||= Adwaita::AboutDialog.new.tap do |dlg|
        dlg.application_name = _("Blanket")
        dlg.application_icon = Define::APP_ID
        dlg.comments = _("Listen to different sounds")
        dlg.copyright = _("Copyright 2020-2022 Rafael Mardojai CM")
        dlg.developer_name = "Rafael Mardojai CM"
        dlg.developers = Define::AUTHORS
        dlg.designers = Define.credits_list(Define::ARTISTS)
        dlg.website = "https://apps.gnome.org/Blanket"
        dlg.issue_url = "https://github.com/rafaelmardojai/blanket/issues"
        dlg.license_type = Gtk::License::GPL_3_0
        dlg.version = Define::VERSION
        # Upstream's string is the gettext "translator-credits" marker, which
        # each catalogue replaces with its translators' names.
        dlg.translator_credits = _("translator-credits")
      end
    end
  end
end
