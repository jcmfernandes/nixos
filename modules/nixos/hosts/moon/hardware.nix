{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.moonHardware = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # USB-attached SATA HDDs. The `dataN` label is what crypttab maps
    # the unlocked device to (/dev/mapper/data1 etc.), preserved across
    # the refactor so filesystem mounts in configuration.nix continue
    # to work. To swap a physical drive, change one line here.
    disks = {
      data1 = "/dev/disk/by-id/ata-ST2000DM008-2UB102_ZK20L15W";
      data2 = "/dev/disk/by-id/ata-ST2000DM008-2UB102_ZK20L42Q";
      data3 = "/dev/disk/by-id/ata-ST2000DM008-2UB102_ZK30LJ0R";
    };
    diskList = lib.attrValues disks;

    rpiPackages = inputs.nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system};
  in {
    imports = with inputs.nixos-raspberrypi.nixosModules; [
      raspberry-pi-5.base
      raspberry-pi-5.page-size-16k
      raspberry-pi-5.display-vc4
    ];

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    # nixpkgs 26.11 moved the kernel's `target` and `buildDTBs` from
    # stdenv.hostPlatform.linux-kernel onto the kernel package's passthru.
    # raspberry-pi-5.base sets boot.kernelPackages from nixos-raspberrypi's
    # *own* flake outputs, which are built against its pinned (older)
    # nixpkgs -- so the package predates that move while the NixOS modules
    # reading it are 26.11. Result: "attribute 'buildDTBs' missing"
    # (nixpkgs' hardware/device-tree.nix) and "attribute 'target' missing"
    # (nixos-raspberrypi's own bootloader module, which already branches on
    # release >= 26.11). Upstream issue:
    # https://github.com/nvmd/nixos-raspberrypi/issues/201
    #
    # Re-add the two attributes. They land in passthru, which is not a
    # derivation input, so drvPath/outPath are unchanged and the kernel
    # still comes from nixos-raspberrypi.cachix.org. overrideAttrs rather
    # than `//`: boot.kernelPackages' own `apply` calls `kernel.override`,
    # which re-runs the package function and drops `//` additions, while
    # overrideAttrs survives it. The values are what our nixpkgs computes
    # for the same kernel (pkgs.linux_rpi5.{target,buildDTBs}).
    #
    # Drop this once nixos-raspberrypi ships a 26.11-compatible kernel.
    boot.kernelPackages = rpiPackages.linuxPackages_rpi5.extend (_: kprev: {
      kernel = kprev.kernel.overrideAttrs (old: {
        passthru =
          (old.passthru or {})
          // {
            target = "Image";
            buildDTBs = true;
          };
      });
    });

    networking.hostId = "cdbfae8b";

    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/NIXOS_SD";
        fsType = "ext4";
        options = ["noatime"];
      };
      "/boot/firmware" = {
        device = "/dev/disk/by-label/FIRMWARE";
        fsType = "vfat";
        options = ["noatime" "nofail"];
      };
    };

    boot.loader.raspberry-pi.bootloader = "kernel";
    boot.kernel.sysctl = {
      "vm.overcommit_memory" = lib.mkForce "1";
    };

    # smartd device list (merged with the rest of services.smartd's
    # settings — enable/notifications/defaults — in configuration.nix).
    services.smartd.devices = map (d: {device = d;}) diskList;

    # Spin down idle disks after 10 min. One -a per device.
    systemd.services.hd-idle = {
      description = "Spin down idle USB disks";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 10;
        ExecStart =
          "${pkgs.hd-idle}/bin/hd-idle -i 0 -l /var/log/hd-idle.log "
          + lib.concatMapStringsSep " " (d: "-a ${d} -i 600") diskList;
      };
    };

    # LUKS crypttab generated from the disks attrset. Keep `dataN`
    # names stable — fileSystems."/mnt/diskN" mounts /dev/mapper/dataN.
    environment.etc."crypttab".text =
      lib.concatMapStringsSep "\n"
      (name: "${name} ${disks.${name}}-part1 /var/lib/luks-keys/das.key luks")
      (lib.attrNames disks)
      + "\n";
  };
}
