# frozen_string_literal: true

require_relative "rb/version"

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
        name:   "Nature",
        sounds: [
          {name: "rain", title: "Rain"},
          {name: "storm", title: "Storm"},
          {name: "wind", title: "Wind"},
          {name: "waves", title: "Waves"},
          {name: "stream", title: "Stream"},
          {name: "birds", title: "Birds"},
          {name: "summer-night", title: "Summer Night"},
        ],
      },
      {
        name:   "Travel",
        sounds: [
          {name: "train", title: "Train"},
          {name: "boat", title: "Boat"},
          {name: "city", title: "City"},
        ],
      },
      {
        name:   "Interiors",
        sounds: [
          {name: "coffee-shop", title: "Coffee Shop"},
          {name: "fireplace", title: "Fireplace"},
        ],
      },
    ].freeze

    NOISES = [
      {name: "pink-noise", title: "Pink Noise"},
      {name: "white-noise", title: "White Noise"},
    ].freeze

    AUTHORS = ["Rafael Mardojai CM"].freeze

    ARTISTS = {
      "Jakub Steiner"      => ["Sounds icons"],
      "Rafael Mardojai CM" => ["App icon"],
    }.freeze

    SOUND_ARTISTS = {
      "alex36917"      => ["Rain"],
      "Digifish music" => ["Storm"],
      "ezwa"           => ["Fireplace"],
      "Falcet"         => ["Boat"],
      "gezortenplotz"  => ["City"],
      "gluckose"       => ["Stream"],
      "Jorge Stolfi"   => ["White Noise"],
      "kvgarlic"       => ["Birds"],
      "Lisa Redfern"   => ["Summer Night"],
      "Luftrum"        => ["Waves"],
      "stephan"        => ["Coffee Shop"],
      "Omegatron"      => ["Pink Noise"],
      "felix.blume"    => ["Wind"],
      "SDLx"           => ["Train"],
    }.freeze

    SOUND_EDITORS = {
      "Porrumentzio" => [
        "Birds",
        "Rain",
        "Storm",
        "Waves",
        "Boat",
        "City",
        "Wind",
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
