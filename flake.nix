{
  description = "Legato downstream — dev + Pi 4B deploy";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    legato.url = "github:legato-dsp/legato";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
  };

  outputs = { self, nixpkgs, legato, nixos-hardware, rust-overlay, crane }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f system);

      mkPkgs = system: import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
      };

      mkToolchain = pkgs: pkgs.rust-bin.selectLatestNightlyWith
        (t: t.default.override { extensions = [ "rust-src" ]; });

      mkApp = system:
        let
          pkgs = mkPkgs system;
          toolchain = mkToolchain pkgs;
          craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;
          rtDeps = pkgs.lib.optionals pkgs.stdenv.isLinux
            (with pkgs; [ alsa-lib jack2 udev ]);
        in
        craneLib.buildPackage {
          src = craneLib.cleanCargoSource ./src-legato;
          strictDeps = true;
          nativeBuildInputs = with pkgs; [ pkg-config clang ];
          buildInputs = rtDeps;
          RUSTFLAGS = pkgs.lib.optionalString pkgs.stdenv.isx86_64
            "-C target-cpu=x86-64-v3";
        };
    in
    {
      packages = forAll (system: {
        default = mkApp system;
      });

      devShells = forAll (system:
        let pkgs = mkPkgs system; in {
          default = pkgs.mkShell {
            inputsFrom = [ legato.devShells.${system}.default ];
            packages = [
              (pkgs.writeShellScriptBin "run-release" ''
                exec cargo run --release --manifest-path ./src-legato/Cargo.toml "$@"
              '')
            ];
          };
        });

      nixosConfigurations.pi = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          nixos-hardware.nixosModules.raspberry-pi-4
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          ./pi/configuration.nix
          { nixpkgs.overlays = [
              (_: _: { legato-app = self.packages.aarch64-linux.default; })
          ]; }
          ({pkgs, ...}: {
            systemd.services.legato = 
              let graphFile = pkgs.writeText ".legato" ''
                audio {
                  sine { freq: 440.0 },
                  mono_fan_out { chans: 2 }
                }

                sine >> mono_fan_out

                { mono_fan_out }
              ''; 
                in      
              {
              description = "Legato DSP (CPAL/ALSA)";
              wantedBy = [ "multi-user.target" ];
              after = [ "sound.target" ];
              environment = {
                LEGATO_SAMPLE_RATE = "48000";
                LEGATO_BLOCK_SIZE = "64";
                LEGATO_CHANNELS = "2";
                LEGATO_GRAPH = "${graphFile}";
              };
              serviceConfig = {
                User = "luke";
                ExecStart = "${pkgs.legato-app}/bin/legato-template";
                LimitRTPRIO = 99;
                LimitMEMLOCK = "infinity";
                Restart = "on-failure";
                RestartSec = 2;
              };
            };
          })
        ];
      };
    };
}