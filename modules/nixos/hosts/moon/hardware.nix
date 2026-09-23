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
      # Not raspberry-pi-5.page-size-16k: it only rebuilds the shared
      # jemalloc for 16 KiB pages, a memory optimization (its README calls
      # it optional and warns it "may cause lots of rebuilds"). jemalloc
      # needs its page setting to be at least the system's, and nixpkgs'
      # default is 64 KiB, so the stock one already works on this kernel.
      # With it, jemalloc -> rustc -> every Rust package missed the cache.
      raspberry-pi-5.display-vc4
    ];

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    # nixos-raspberrypi pins its own nixpkgs to 26.05, the same release
    # moon builds from, so the kernel package and the NixOS modules that
    # read it agree and no passthru patching is needed. If moon is ever
    # moved to a newer channel ahead of nixos-raspberrypi, the `target` /
    # `buildDTBs` mismatch comes back -- see the workaround in this file's
    # history and https://github.com/nvmd/nixos-raspberrypi/issues/201.
    boot.kernelPackages = rpiPackages.linuxPackages_rpi5;

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
