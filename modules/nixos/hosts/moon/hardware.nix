{ self, inputs, ... }: {

  flake.nixosModules.moonHardware = { config, lib, pkgs, ... }: let
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
  in {
    imports = with inputs.nixos-raspberrypi.nixosModules; [
      raspberry-pi-5.base
      raspberry-pi-5.page-size-16k
      raspberry-pi-5.display-vc4
    ];

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    networking.hostId = "cdbfae8b";

    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/NIXOS_SD";
        fsType = "ext4";
      };
      "/boot/firmware" = {
        device = "/dev/disk/by-label/FIRMWARE";
        fsType = "vfat";
        options = [ "noatime" "nofail" ];
      };
    };

    boot.loader.raspberry-pi.bootloader = "kernel";
    boot.kernel.sysctl = {
      "vm.overcommit_memory" = lib.mkForce "1";
    };

    # smartd device list (merged with the rest of services.smartd's
    # settings — enable/notifications/defaults — in configuration.nix).
    services.smartd.devices = map (d: { device = d; }) diskList;

    # Spin down idle disks after 10 min. One -a per device.
    systemd.services.hd-idle = {
      description = "Spin down idle USB disks";
      wantedBy = [ "multi-user.target" ];
      after    = [ "local-fs.target" ];
      serviceConfig = {
        Type       = "simple";
        Restart    = "always";
        RestartSec = 10;
        ExecStart  =
          "${pkgs.hd-idle}/bin/hd-idle -i 0 -l /var/log/hd-idle.log "
          + lib.concatMapStringsSep " " (d: "-a ${d} -i 600") diskList;
      };
    };

    # LUKS crypttab generated from the disks attrset. Keep `dataN`
    # names stable — fileSystems."/mnt/diskN" mounts /dev/mapper/dataN.
    environment.etc."crypttab".text = lib.concatMapStringsSep "\n"
      (name: "${name} ${disks.${name}}-part1 /var/lib/luks-keys/das.key luks")
      (lib.attrNames disks) + "\n";
  };

}
