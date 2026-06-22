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
                patch basic_verb(){
                    in audio_in
                    audio {
                        svf: input_hp { type: "highpass", cutoff: 120.0, q: 0.7, chans: 2 },
                        svf: input_lp { type: "lowpass", cutoff: 8000.0, q: 0.7, chans: 2 },
                        svf: loop_shelf { type: "lowshelf", cutoff: 300.0, gain: -6.0, q: 0.7, chans: 8 },

                        // Input diffusion (stereo)
                        allpass: pre_ap1 { delay_length: 13.0, feedback: 0.4, chans: 2 },
                        allpass: pre_ap2 { delay_length: 31.0, feedback: 0.4, chans: 2 },
                        allpass: pre_ap3 { delay_length: 59.0, feedback: 0.4, chans: 2 },
                        allpass: pre_ap4 { delay_length: 71.0, feedback: 0.4, chans: 2 },
                        allpass: pre_ap5 { delay_length: 97.0, feedback: 0.4, chans: 2 },
                        allpass: pre_ap6 { delay_length: 113.0, feedback: 0.4, chans: 2 },
                        allpass: pre_ap7 { delay_length: 137.0, feedback: 0.4, chans: 2 },

                        // 4 independent stereo delay lines
                        delay_write: dw1 { delay_name: "d_a", delay_length: 700.0,  chans: 2 },
                        delay_write: dw2 { delay_name: "d_b", delay_length: 1000.0, chans: 2 },
                        delay_write: dw3 { delay_name: "d_c", delay_length: 1500.0, chans: 2 },
                        delay_write: dw4 { delay_name: "d_d", delay_length: 2500.0, chans: 2 },

                        delay_read: dr1 { delay_name: "d_a", chans: 2, delay_length: [ 557,  613  ] },
                        delay_read: dr2 { delay_name: "d_b", chans: 2, delay_length: [ 809,  877  ] },
                        delay_read: dr3 { delay_name: "d_c", chans: 2, delay_length: [ 1201, 1327 ] },
                        delay_read: dr4 { delay_name: "d_d", chans: 2, delay_length: [ 2137, 2311 ] },

                        // Per-tap diffusers
                        allpass: ap_tap1 { delay_length: 17.0, feedback: 0.4, chans: 2 },
                        allpass: ap_tap2 { delay_length: 23.0, feedback: 0.4, chans: 2 },
                        allpass: ap_tap3 { delay_length: 31.0, feedback: 0.4, chans: 2 },
                        allpass: ap_tap4 { delay_length: 41.0, feedback: 0.4, chans: 2 },

                        hadamard { chans: 8 },
                        hadamard: input_had { chans: 8 },

                        onepole { cutoff: 2000.0, chans: 8 },

                        // Loop allpasses
                        allpass: loop_ap1 { delay_length: 5.0,  feedback: 0.2, chans: 8 },
                        allpass: loop_ap2 { delay_length: 9.0,  feedback: 0.2, chans: 8 },
                        allpass: loop_ap3 { delay_length: 14.0, feedback: 0.2, chans: 8 },
                        allpass: loop_ap4 { delay_length: 19.0, feedback: 0.2, chans: 8 },

                        sine: lfo1 { freq: 0.11 },
                        sine: lfo2 { freq: 0.13 },
                        sine: lfo3 { freq: 0.17 },
                        sine: lfo4 { freq: 0.19 },
                        sine: lfo5 { freq: 0.07 },
                        sine: lfo6 { freq: 0.23 },

                        track_mixer: feedback    { tracks: 4, chans_per_track: 2, gain: [0.3, 0.3, 0.3, 0.3] },
                        track_mixer: hm_mix_down { tracks: 4, chans_per_track: 2, gain: [0.5, 0.5, 0.5, 0.5] },
                        track_mixer: wet_dry     { tracks: 2, chans_per_track: 2, gain: [0.5, 0.5] },
                    }

                    control {
                        map: lfo1_map { range: [-1.0, 1.0], new_range: [4.0,  6.0 ] },  // loop_ap1 base 5ms
                        map: lfo2_map { range: [-1.0, 1.0], new_range: [7.5,  10.5] },  // loop_ap2 base 9ms
                        map: lfo3_map { range: [-1.0, 1.0], new_range: [13.0, 15.0] },  // loop_ap3 base 14ms
                        map: lfo4_map { range: [-1.0, 1.0], new_range: [17.5, 20.5] },  // loop_ap4 base 19ms

                        map: lfo5_map { range: [-1.0, 1.0], new_range: [15.0, 19.0] },  // ap_tap1 base 17ms
                        map: lfo6_map { range: [-1.0, 1.0], new_range: [28.0, 34.0] },  // ap_tap3 base 31ms
                    }

                    // LFO chains
                    lfo1 >> lfo1_map >> loop_ap1.delay_length
                    lfo2 >> lfo2_map >> loop_ap2.delay_length
                    lfo3 >> lfo3_map >> loop_ap3.delay_length
                    lfo4 >> lfo4_map >> loop_ap4.delay_length

                    lfo5 >> lfo5_map >> ap_tap1.delay_length
                    lfo6 >> lfo6_map >> ap_tap3.delay_length

                    audio_in >> input_hp[0..2] >> input_lp[0..2] >> pre_ap1[0..2]
                    pre_ap1[0..2] >> pre_ap2[0..2] >> pre_ap3[0..2] >> pre_ap4[0..2] >> pre_ap5[0..2] >> pre_ap6[0..2] >> pre_ap7[0..2]

                    pre_ap7[0..2] >> input_had[0..2]
                    pre_ap7[0..2] >> input_had[2..4]
                    pre_ap7[0..2] >> input_had[4..6]
                    pre_ap7[0..2] >> input_had[6..8]

                    input_had[0..2] >> dw1
                    input_had[2..4] >> dw2
                    input_had[4..6] >> dw3
                    input_had[6..8] >> dw4

                    dr1 >> ap_tap1[0..2] >> hadamard[0..2]
                    dr2 >> ap_tap2[0..2] >> hadamard[2..4]
                    dr3 >> ap_tap3[0..2] >> hadamard[4..6]
                    dr4 >> ap_tap4[0..2] >> hadamard[6..8]

                    hadamard >> onepole[0..8] >> loop_shelf[0..8] >> loop_ap1[0..8] >> loop_ap2[0..8] >> loop_ap3[0..8] >> loop_ap4[0..8]

                    loop_ap4    >> hm_mix_down
                    hm_mix_down >> wet_dry[2..4]
                    audio_in    >> wet_dry[0..2]

                    loop_ap4       >> feedback
                    feedback[0..2] >> dw1
                    feedback[2..4] >> dw2
                    feedback[4..6] >> dw3
                    feedback[6..8] >> dw4

                    { wet_dry }
                }

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
                    basic_verb { }
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

                pan >> basic_verb

                { basic_verb }
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