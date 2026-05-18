{ ... }: {
  # Exposed as a flake-parts output so the file isn't accidentally loaded
  # as a top-level flake module by `import-tree`. Imported into vivivi's
  # NixOS config via `self.diskoConfigurations.vivivi` — same pattern as
  # karma.
  flake.diskoConfigurations.vivivi = {
    # OCI A1.Flex boot disk is /dev/sda. Single GPT layout: BIOS-boot stub
    # for safety, EFI system partition (UEFI is what OCI actually uses),
    # root.
    disko.devices.disk.main = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02";
          };
          esp = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
