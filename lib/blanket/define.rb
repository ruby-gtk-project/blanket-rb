# frozen_string_literal: true

require_relative "rb/version"
require_relative "i18n"

module Blanket
  # Ported from blanket/define.in.
  #
  # Upstream's define.in is a Meson-templated module holding the app id, the
  # resource prefix, the sound catalogue and the credits tables. The templating
  # has no counterpart here — the values are literals and the version comes
  # from the gem — and the resource prefix is joined by the directory layout
  # the port reads its assets from, since this port ships its sounds, icons and
  # stylesheet as files rather than as a compiled GResource bundle.
  module Define
    include GetText

    VERSION = Blanket::Rb::VERSION
    APP_ID = "org.rubygtkproject.Blanket"
    RES_PATH = "/org/rubygtkproject/Blanket"

    # Where the assets upstream compiles into a GResource bundle live instead.
    DATA_DIR = File.expand_path("../../data", __dir__)
    ICONS_DIR = File.join(DATA_DIR, "icons")
    SOUNDS_DIR = File.join(DATA_DIR, "sounds")
    SCHEMAS_DIR = File.join(DATA_DIR, "schemas")
    STYLE_PATH = File.expand_path("style.css", __dir__)

    SOUNDS = [
      {
        name:   _("Nature"),
        sounds: [
          {name: "rain", title: _("Rain")},
          {name: "storm", title: _("Storm")},
          {name: "wind", title: _("Wind")},
          {name: "waves", title: _("Waves")},
          {name: "stream", title: _("Stream")},
          {name: "birds", title: _("Birds")},
          {name: "summer-night", title: _("Summer Night")},
        ],
      },
      {
        name:   _("Travel"),
        sounds: [
          {name: "train", title: _("Train")},
          {name: "boat", title: _("Boat")},
          {name: "city", title: _("City")},
        ],
      },
      {
        name:   _("Interiors"),
        sounds: [
          {name: "coffee-shop", title: _("Coffee Shop")},
          {name: "fireplace", title: _("Fireplace")},
        ],
      },
    ].freeze

    NOISES = [
      {name: "pink-noise", title: _("Pink Noise")},
      {name: "white-noise", title: _("White Noise")},
    ].freeze

    AUTHORS = ["Rafael Mardojai CM"].freeze

    ARTISTS = {
      "Jakub Steiner"      => [_("Sounds icons")],
      "Rafael Mardojai CM" => [_("App icon")],
    }.freeze

    SOUND_ARTISTS = {
      "alex36917"      => [_("Rain")],
      "Digifish music" => [_("Storm")],
      "ezwa"           => [_("Fireplace")],
      "Falcet"         => [_("Boat")],
      "gezortenplotz"  => [_("City")],
      "gluckose"       => [_("Stream")],
      "Jorge Stolfi"   => [_("White Noise")],
      "kvgarlic"       => [_("Birds")],
      "Lisa Redfern"   => [_("Summer Night")],
      "Luftrum"        => [_("Waves")],
      "stephan"        => [_("Coffee Shop")],
      "Omegatron"      => [_("Pink Noise")],
      "felix.blume"    => [_("Wind")],
      "SDLx"           => [_("Train")],
    }.freeze

    SOUND_EDITORS = {
      "Porrumentzio" => [
        _("Birds"),
        _("Rain"),
        _("Storm"),
        _("Waves"),
        _("Boat"),
        _("City"),
        _("Wind"),
      ],
    }.freeze

    # The URI a bundled sound is decoded from. Upstream reads
    # "resource:/com/rafaelmardojai/Blanket/sounds/<name>.ogg"; the port's
    # sounds are files next to the code.
    def self.sound_uri(name) = "file://#{File.join(SOUNDS_DIR, "#{name}.ogg")}"

    # Flattens one of the credits tables above into the "Name: a, b" lines
    # Adw.AboutDialog's credit sections take. Ported from main.py's
    # __get_credits_list.
    def self.credits_list(table) = table.map { |name, works| "#{name}: #{works.join(", ")}" }
  end
end
