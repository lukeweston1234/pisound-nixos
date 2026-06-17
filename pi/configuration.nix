{ config, lib, pkgs, modulesPath, ...}:

{
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  boot.supportedFilesystems = lib.mkForce [ "ext4" "vfat" ];

  boot.kernelModules = [ "snd-soc-pisound" ];

  boot.initrd = {

    availableKernelModules = {
      "xhci_pci" = true;
      "usbhid" = true;
      "usb_storage" = true;
      # todo: remove this when this is fixed: https://github.com/NixOS/nixpkgs/issues/154163
      # related: https://github.com/NixOS/nixpkgs/issues/109280
      # related: https://discourse.nixos.org/t/cannot-build-raspberry-pi-sdimage-module-dw-hdmi-not-found/71804
      dw-hdmi = lib.mkForce false;
      dw-mipi-dsi = lib.mkForce false;
      rockchipdrm = lib.mkForce false;
      rockchip-rga = lib.mkForce false;
      phy-rockchip-pcie = lib.mkForce false;
      pcie-rockchip-host = lib.mkForce false;
      pwm-sun4i = lib.mkForce false;
      sun4i-drm = lib.mkForce false;
      sun8i-mixer = lib.mkForce false;
    };
  };

  services.openssh.enable = true;

  systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];

  nix.settings.trusted-users = [ "luke" ];

  security.sudo.wheelNeedsPassword = false;

  hardware = {
    raspberry-pi."4".apply-overlays-dtmerge.enable = true;
    deviceTree = {
      enable = true;
      filter = "*rpi-4-*.dtb";
      overlays = [
        {
          name = "pisound";
          dtboFile = "${config.boot.kernelPackages.kernel}/dtbs/overlays/pisound.dtbo";
        }
        {
          name = "disable-bt";
          dtboFile = "${config.boot.kernelPackages.kernel}/dtbs/overlays/disable-bt.dtbo";
        }
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
    alsa-utils
  ];

  security.rtkit.enable = true;
  security.pam.loginLimits = [
    { domain = "@audio"; item = "rtprio";  type = "-"; value = "99"; }
    { domain = "@audio"; item = "memlock"; type = "-"; value = "unlimited"; }
  ];

  services.pulseaudio.enable = false;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
  };

  users.users.luke = {
    isNormalUser = true;
    extraGroups = [ "wheel" "audio" ];
    initialPassword = "password";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDWvvcvKsuBIm9Cawq4Ay+W10KKd/NgCrOmpBZjnE/5D816Odyrtd/jGh7zhcjqaLOEy8WE+I/7Yx6aNovclSRaAEpNli5wq5DZFCIy9/zMn9D5Hbh0FDLtsu8ucopixJwlDDKAT50NMgfd3H8EEYx1NY3jTm3SyBHXhp6asPcLGAUTmaG789GSUKDyyDV1tq6nyDgIXhj9npJTBGJ6HvT5mHLJQg1NpflLibMtbapf4z+IYJINMWPX3KgLWsIS476QYodIdRKd0Ylc3fJPTanXlZjlDrMDKCaotyUekC2mFMDVbJVn7kJ5sAc/Bc+KyWfdy1NEpKpB+G2jCnCZEVz4vpuv1qT8Ke+WXeZPc2q2PNs5hyylNkbWQhvCvn5WfSyxSAUg78VqO/BrLJyCLSXLurVHdWJG+x1XdRPxZjTijVtSmhIp0PJ0g34a2BOIqfqCVlRHOKmCGMFIoD/Z+pPZeOzJx9YYBN/9+8RQGYaYPPnbkkpmjwNTju7UoUwZT3M= luke@nixos"
    ];
  };

  networking.networkmanager.enable = true;
  networking.useDHCP = lib.mkDefault true;

  time.timeZone = "Europe/Berlin";

  system.stateVersion = "25.11";
}