**WARNING:**

**This is a personal WIP repository, will add my SSH public key, etc. Just for reference for now until I make a nicer solution for downstream users**

**Use or take inspiration at your own risk!**

Initial USB Flash

```sh 
nix build .#nixosConfigurations.pi.config.system.build.sdImage

zstd -dc result/sd-image/nixos-image-sd-card-26.11.20260610.9ae611a-aarch64-linux.img.zst | 
sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

Remote Deployment

```sh
nixos-rebuild switch \
  --flake .#pi \
  --target-host luke@10.1.0.188 \
  --use-remote-sudo
```