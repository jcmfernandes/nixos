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
    # Real hardware (AMD laptop), not a qemu guest. The boot modules below
    # match `nixos-generate-config --show-hardware-config` run on the machine
    # itself: one NVMe disk, no SATA controller, so none of the ahci/SCSI/
    # usb-storage baseline is reachable at initrd time.
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "usbhid"];
    # LVM, as karma.
    boot.initrd.kernelModules = ["dm-snapshot"];
    boot.kernelModules = ["kvm-amd"];
    boot.extraModulePackages = [];

    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    networking.useDHCP = lib.mkDefault true;

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  };
}
