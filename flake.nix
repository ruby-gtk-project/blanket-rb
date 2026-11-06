{
  description = "blanket — a Ruby GTK4 port";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Shared libraries every ruby-gnome extension links against.
        gtkStack = with pkgs; [
          glib
          gobject-introspection
          cairo
          pango
          gdk-pixbuf
          graphene
          atk
          gtk4
          libadwaita
          harfbuzz
          librsvg
        ]
        # The Ruby `pkg-config` gem resolves `Requires.private` transitively and
        # hard-fails if any .pc in the chain is missing, so gtk4's whole private
        # closure has to be on PKG_CONFIG_PATH, not just its public deps.
        ++ (with pkgs; [
          fontconfig
          freetype
          libepoxy
          libpng
          libxkbcommon
          pcre2
          util-linux
          wayland
          zlib
          fribidi
          libdatrie
          libthai
          libselinux
          libsepol
          expat
          brotli
          bzip2
          graphite2
          icu
          libffi
          libxml2
          lerc
          libdeflate
          xz
          zstd
        ])
        # Un-prefixed names: the `xorg.*` package set is deprecated.
        ++ (with pkgs; [
          libx11
          libxau
          libxcursor
          libxdmcp
          libxext
          libxfixes
          libxi
          libxinerama
          libxrandr
          libxrender
          libxcb
          xorgproto
        ]);

        # The app is a GStreamer mixer: every sound is a branch of one shared
        # pipeline. gst-plugins-base carries audiomixer, audioconvert,
        # audioresample, volume, audiotestsrc, capsfilter and the decodebin
        # family; gst-plugins-good carries the Ogg/Vorbis decoders the bundled
        # sounds need and the PulseAudio sink `autoaudiosink` picks.
        gstStack = with pkgs.gst_all_1; [
          gstreamer
          gst-plugins-base
          gst-plugins-good
        ];

        # Where GStreamer looks for its element factories. Without it the
        # pipeline builds no elements at all and every sound reports failure.
        gstPluginPath = pkgs.lib.makeSearchPath "lib/gstreamer-1.0"
          (map (drv: drv.out or drv) gstStack);

        # ruby-gnome gems build C extensions with extconf.rb + the pkg-config
        # gem; nixpkgs only ships gemConfig entries for the GTK3-era subset, so
        # the GTK4 gems get their build inputs declared here.
        rubyGnomeGem = _attrs: {
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = gtkStack;
        };

        # The gstreamer gem builds a C extension of its own against
        # gstreamer-1.0.pc and gstreamer-audio-1.0.pc. Those name libunwind,
        # libdw (elfutils) and orc-0.4 in `Requires.private`, and the
        # pkg-config gem hard-fails on any .pc missing from that chain, so
        # all three are build inputs here too.
        rubyGstGem = _attrs: {
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = gtkStack ++ gstStack ++ (with pkgs; [ libunwind elfutils orc ]);
        };

        gemConfig = pkgs.defaultGemConfig // {
          gstreamer = rubyGstGem;
          gdk4 = rubyGnomeGem;
          gsk4 = rubyGnomeGem;
          gtk4 = rubyGnomeGem;
          graphene1 = rubyGnomeGem;
          adwaita = rubyGnomeGem;
          rsvg2 = rubyGnomeGem;
        };

        # `makeSearchPath` would take each package's *first* output, and glib's
        # first output is `bin`, which carries no typelibs — hence the explicit
        # `.out`. at-spi2-core is here for the Atk typelib.
        typelibPath = pkgs.lib.makeSearchPath "lib/girepository-1.0"
          (map (drv: drv.out or drv) (gtkStack ++ gstStack ++ [ pkgs.at-spi2-core ]));

        # ashpd carries a Rust extension, and its precompiled platform gems need no
        # compiler. Gemfile.lock names every platform the gem ships, so bundix writes
        # the one entry it always writes: no platform, and the source gem's hash --
        # which would want cargo to build it, and fails here as
        #   hash mismatch in fixed-output derivation 'ashpd-0.1.1.gem.drv'
        # because the fetch gets a platform gem and the lock recorded the source one.
        #
        # The platform belongs to the system being built for rather than to the
        # lockfile, so the entry is rewritten into the platform gem for this system.
        # This is the pattern gnome-maps-rb uses for the same gem.
        #
        # These hashes are for the version Gemfile.lock resolves: a bump needs them
        # recomputed with
        #   nix-prefetch-url https://rubygems.org/downloads/ashpd-<v>-<platform>.gem
        ashpdPlatforms = {
          x86_64-linux  = { platform = "x86_64-linux";  sha256 = "0pnjv2rszvd10dvn3qmgf5vlkgmkjnkj18phvbvaya1arsm3ph9s"; };
          aarch64-linux = { platform = "aarch64-linux"; sha256 = "156x0l8fal0n05k6ya6qdfgl8277595mrg6gx0syis6dx3rr8fk7"; };
          x86_64-darwin = { platform = "x86_64-darwin"; sha256 = "0dq81l7pkmxpkxp9i6g3wwdj9pynp4jl691sw8d6q58qww5a2ag8"; };
          aarch64-darwin = { platform = "arm64-darwin"; sha256 = "19xfp65ag0mmp55kkwwq9qg0vmm1pxfswf9qca55b81k9phw2bbq"; };
        };

        blanketGemset = import ./nix/gemset.nix;

        ashpdGem =
          let
            selected = ashpdPlatforms.${system} or (throw
              "ashpd has no precompiled gem for ${system}");
            generic = blanketGemset.ashpd;
          in
          generic // {
            version = "${generic.version}-${selected.platform}";
            source = generic.source // { sha256 = selected.sha256; };
          };

        # nix/ and not the repo root: the root Gemfile is kettle-jem's
        # development bundle — rubocop, rspec, yard, the kettle-dev stack — and
        # must not end up in a packaged app's runtime closure. nix/Gemfile holds
        # the gemspec's runtime dependencies only.
        #
        # gemfile/lockfile/gemset explicitly rather than `gemdir`, because the
        # gemset is patched above to select ashpd's platform gem; gemdir would
        # read nix/gemset.nix unmodified and fetch the source gem.
        gems = pkgs.bundlerEnv {
          name = "blanket-gems";
          ruby = pkgs.ruby_3_4;
          inherit gemConfig;
          gemfile = ./nix/Gemfile;
          lockfile = ./nix/Gemfile.lock;
          gemset = blanketGemset // { ashpd = ashpdGem; };
        };

        # The launcher is whatever the gemspec installs into exe/. Reading the
        # directory keeps this flake generic: no name to keep in step by hand.
        launcher = builtins.head (builtins.attrNames (builtins.readDir ./exe));

        # Optional directories: a port that has not grown translations or data
        # assets yet simply has none.
        optionalDirs = builtins.filter (d: builtins.pathExists (./. + "/${d}")) [
          "data"
          "po"
        ];
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "blanket";
          version = "0.1.0";
          src = ./.;

          # Deliberately no wrapGAppsHook4: glib's setup hook relocates
          # share/glib-2.0/schemas during fixup, after wrapGAppsHook4 has
          # computed its wrapper arguments, so a schema would end up somewhere
          # the wrapper never looks. The wrapper below is built by hand and
          # points at both the pre- and post-move paths.
          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ gems ] ++ gtkStack ++ gstStack;

          dontBuild = true;

          installPhase = ''
            runHook preInstall

            mkdir -p $out/share/blanket
            cp -r lib $out/share/blanket/
            for d in ${pkgs.lib.escapeShellArgs optionalDirs}; do
              cp -r "$d" $out/share/blanket/
            done
            # exe/ sits next to lib/ so the launcher's `require "blanket"`
            # resolves against the copied tree.
            install -Dm755 exe/${launcher} $out/share/blanket/exe/${launcher}

            # Compile any GSettings schema the port ships.
            if [ -d data/schemas ]; then
              mkdir -p $out/share/glib-2.0/schemas
              cp data/schemas/*.gschema.xml $out/share/glib-2.0/schemas/
              ${pkgs.glib.dev}/bin/glib-compile-schemas $out/share/glib-2.0/schemas
            fi

            # -rbundler/setup puts the bundled gems on the load path, and
            # GI_TYPELIB_PATH keeps GObject-Introspection from re-registering
            # types the cairo gem's C extension has already registered.
            makeWrapper ${gems.wrappedRuby}/bin/ruby $out/bin/${launcher} \
              --add-flags "-rbundler/setup" \
              --add-flags "-I$out/share/blanket/lib" \
              --add-flags "$out/share/blanket/exe/${launcher}" \
              --set GI_TYPELIB_PATH "${typelibPath}" \
              --set GST_PLUGIN_SYSTEM_PATH_1_0 "${gstPluginPath}" \
              --prefix XDG_DATA_DIRS : "$out/share" \
              --prefix XDG_DATA_DIRS : "$out/share/gsettings-schemas/blanket-0.1.0" \
              --prefix XDG_DATA_DIRS : "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}" \
              --prefix XDG_DATA_DIRS : "${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}" \
              --prefix XDG_DATA_DIRS : "${pkgs.adwaita-icon-theme}/share"

            runHook postInstall
          '';

          meta = {
            description = "A Ruby GTK4 / Libadwaita port of blanket";
            mainProgram = launcher;
            platforms = pkgs.lib.platforms.linux;
          };
        };

        apps.default = utils.lib.mkApp { drv = self.packages.${system}.default; };

        devShells.default = pkgs.mkShell {
          name = "blanket-devshell";

          packages = [
            gems
            gems.wrappedRuby
            pkgs.bundler
            pkgs.bundix
            pkgs.pkg-config
            pkgs.glib.dev
            pkgs.gettext
            # rxgettext, the extractor `rake pot` drives. GNU xgettext claims
            # to support Ruby but only shells out to this, so without it
            # `xgettext --language=Ruby` fails.
            pkgs.rubyPackages_3_4.gettext
            # The spec runner. The suite is plain RSpec, so this is enough.
            pkgs.rubyPackages_3_4.rspec
            # This machine may have no display server at all, so the shell
            # carries one it can start itself: `xvfb-run ruby exe/<app>` both
            # launches the app and is how test/drive_*.rb is run.
            pkgs.xvfb-run
            pkgs.gsettings-desktop-schemas
            pkgs.adwaita-icon-theme
          ] ++ gtkStack ++ gstStack;

          # Icons, GSettings schemas and the GTK portal all resolve through
          # XDG_DATA_DIRS; without these the window opens with blank icons.
          shellHook = ''
            export XDG_DATA_DIRS="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}:${pkgs.adwaita-icon-theme}/share:$XDG_DATA_DIRS"
            export GI_TYPELIB_PATH="${typelibPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
            export GST_PLUGIN_SYSTEM_PATH_1_0="${gstPluginPath}"
            export RUBYLIB="$PWD/lib''${RUBYLIB:+:$RUBYLIB}"
            [ -d data/schemas ] && export GSETTINGS_SCHEMA_DIR="$PWD/data/schemas"
            unset BUNDLE_GEMFILE BUNDLE_FROZEN
            # bundlerEnv installs the platform gem ashpd, so forcing the ruby
            # platform asks bundler for a gem which is not there.
            export BUNDLE_FORCE_RUBY_PLATFORM=false
            echo "blanket devshell — ruby $(ruby -e 'print RUBY_VERSION')"
            echo "run the app:   xvfb-run ruby exe/blanket"
            echo "drive the app: xvfb-run ruby test/drive_*.rb"
            echo "run the specs: ruby -e 'require \"rspec/core\"; exit RSpec::Core::Runner.run([\"--format\", \"progress\", \"--require\", \"spec_helper\", \"spec\"])'"
          '';
        };
      });
}
