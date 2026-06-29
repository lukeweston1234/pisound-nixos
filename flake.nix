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
            (with pkgs; [ alsa-lib jack2 libjack2 udev ]);
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
                patch voice(
                    attack = 50.0,
                    decay = 30.0,
                    sustain = 0.3,
                    release = 50.0
                ) {
                    in freq gate

                    audio {
                        saw { chans: 1 },
                        adsr { attack: $attack, decay: $decay, sustain: $sustain, release: $release, chans: 1 },
                    }

                    freq >> saw
                    gate >> adsr.gate
                    saw >> adsr[1]

                    { adsr }
                }

                patches {
                    voice * 5 { },
                }

                user {
                    plate480 { predelay: 32.0, decay: 0.8, damping: 0.3, mix: 0.8 }
                }

                audio {
                    sine: pan_lfo { freq: 0.3 },
                    pan,
                    svf { chans: 2, cutoff: 3200.0, q: 0.4, type: "lowpass" },
                    track_mixer: osc_mixer { tracks: 5, chans_per_track: 1, gain: [0.1, 0.1, 0.1, 0.1, 0.1] },
                }

                control {
                    map { range: [-1.0, 1.0], new_range: [0.3, 0.7 ] },
                }

                midi {
                    poly_voice { chan: 0, voices: 5 }
                }

                poly_voice[0:13:3] >> voice(*).gate
                poly_voice[1:13:3] >> voice(*).freq
                voice(*) >> osc_mixer[0..5]

                osc_mixer >> svf[0] >> pan[0]

                pan_lfo >> map >> pan.pan

                pan >> plate480

                { plate480 }
              ''; 
                in      
              {
              description = "Legato DSP (CPAL/ALSA)";
              wantedBy = [ "multi-user.target" ];
              after = [ "sound.target" "jack.service" ];
              wants = [ "jack.service" ];
              environment = {
                LEGATO_SAMPLE_RATE = "48000";
                LEGATO_BLOCK_SIZE = "64";
                LEGATO_CHANNELS = "2";
                LEGATO_GRAPH = "${graphFile}";
                LD_LIBRARY_PATH = "${pkgs.libjack2}/lib";
                JACK_DEFAULT_SERVER = "default";
                JACK_PROMISCUOUS_SERVER = "jackaudio";
              };
              serviceConfig = {
                User = "jackaudio";
                Group = "jackaudio";
                ExecStart = "${pkgs.legato-app}/bin/legato-template";
                LimitRTPRIO = 99;
                LimitMEMLOCK = "infinity";
                Restart = "on-failure";
                RestartSec = 60;
              };
            };
          })
        ];
      };
    };
}