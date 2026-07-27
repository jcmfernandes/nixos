{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.anuchkaHardware = {
    config,
    lib,
    pkgs,
    modulesPath,
    ...
  }: {
    # Real hardware (AMD laptop), not a qemu guest. This is a generic
    # AMD/NVMe baseline; refine it from `nixos-generate-config` output on the
    # actual machine (everything here is mkDefault-friendly).
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"];
    # LVM, as karma.
    boot.initrd.kernelModules = ["dm-snapshot"];
    boot.kernelModules = ["kvm-amd"];
    boot.extraModulePackages = [];

    hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

    networking.useDHCP = lib.mkDefault true;

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  };
}
