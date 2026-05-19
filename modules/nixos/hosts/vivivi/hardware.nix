{ self, inputs, ... }: {

  flake.nixosModules.viviviHardware = { config, lib, pkgs, modulesPath, ... }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    # OCI A1.Flex is KVM/QEMU with virtio devices.
    # `nixos-generate-config` detected virtio_pci + virtio_scsi + xhci_pci
    # + usbhid as the minimum. virtio_blk, virtio_mmio, virtio_net are
    # added defensively so a future OCI shape variant that uses different
    # virtio transports still finds the boot disk and NIC in initrd —
    # we've already debugged the "missing virtio_blk" panic once; the
    # ~50 KiB it costs in initrd is cheap insurance.
    boot.initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_blk"
      "virtio_scsi"
      "virtio_mmio"
      "virtio_net"
      "xhci_pci"
      "usbhid"
    ];
    boot.initrd.kernelModules    = [ ];
    boot.kernelModules           = [ ];
    boot.extraModulePackages     = [ ];

    networking.useDHCP = lib.mkDefault true;
  };

}
