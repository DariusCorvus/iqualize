{
  description = "iQualize — System-wide audio equalizer for Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        rust = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };

        # Runtime libraries needed by Tauri on Linux
        runtimeLibs = with pkgs; [
          gtk3
          webkitgtk_4_1
          libsoup_3
          openssl
          pipewire
          libappindicator-gtk3
          librsvg
          gdk-pixbuf
        ];

        # Build-time dependencies
        buildDeps = with pkgs; [
          pkg-config
          gobject-introspection
          rust
          nodejs_22
          nodePackages.pnpm
          cargo-tauri
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = buildDeps ++ runtimeLibs ++ (with pkgs; [
            # Development tools
            rust-analyzer
          ]);

          nativeBuildInputs = with pkgs; [
            pkg-config
            gobject-introspection
          ];

          shellHook = ''
            export PKG_CONFIG_PATH="${pkgs.pipewire.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:$PKG_CONFIG_PATH"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}:$LD_LIBRARY_PATH"
            export GIO_MODULE_DIR="${pkgs.glib-networking}/lib/gio/modules"
            echo "iQualize Linux dev shell ready"
            echo "Run: pnpm install && cargo tauri dev"
          '';
        };

        # Package build (for nix build)
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "iqualize";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = buildDeps ++ [ pkgs.makeWrapper ];
          buildInputs = runtimeLibs;

          buildPhase = ''
            export HOME=$TMPDIR
            pnpm install --frozen-lockfile
            cargo tauri build --bundles none
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp src-tauri/target/release/iqualize-linux $out/bin/iqualize

            # Wrap with runtime library paths
            wrapProgram $out/bin/iqualize \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeLibs}"

            # Desktop entry
            mkdir -p $out/share/applications
            cat > $out/share/applications/iqualize.desktop << EOF
            [Desktop Entry]
            Type=Application
            Name=iQualize
            Comment=System-wide audio equalizer
            Exec=$out/bin/iqualize
            Icon=iqualize
            Categories=AudioVideo;Audio;Mixer;
            Keywords=equalizer;audio;eq;
            StartupNotify=true
            EOF
          '';
        };
      }
    );
}
