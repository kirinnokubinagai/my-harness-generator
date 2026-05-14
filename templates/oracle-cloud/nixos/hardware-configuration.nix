{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot = {
    initrd = {
      availableKernelModules = [ "virtio_pci" "virtio_blk" "xhci_pci" "usbhid" "sd_mod" ];
      kernelModules = [ ];
    };
    kernelModules = [ ];
    extraModulePackages = [ ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
