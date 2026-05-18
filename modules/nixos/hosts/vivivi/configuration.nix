{ self, inputs, ... }: {

  flake.nixosModules.viviviConfiguration = { config, pkgs, lib, ... }: let
    jcmfernandesAuthorizedKeys = lib.filter (s: s != "")
      (lib.splitString "\n" (lib.fileContents inputs.jcmfernandes-keys));
  in {
    imports = [
      self.nixosModules.base
      self.nixosModules.general
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      self.diskoConfigurations.vivivi
    ];

    nixpkgs.hostPlatform = "aarch64-linux";

    # 16 KiB pages so binaries built here run natively on moon.
    boot.kernelPatches = [{
      name = "arm64-16k-pages";
      patch = null;
      extraStructuredConfig = with lib.kernel; {
        ARM64_16K_PAGES = yes;
        ARM64_4K_PAGES  = lib.mkForce no;
        ARM64_64K_PAGES = lib.mkForce no;
      };
    }];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # OCI A1.Flex is KVM/QEMU under the hood. The auto-detected default
    # initrd module set for aarch64-linux + our custom 16 KiB kernel ends
    # up missing virtio_blk; without it stage-1 can't find /dev/sda and
    # panics with "Attempted to kill init". Pin the cloud-VM modules
    # explicitly so the boot disk shows up before LVM/disko mount.
    boot.initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_blk"
      "virtio_scsi"
      "virtio_mmio"
      "virtio_net"
    ];

    # Same workaround as moon: tikv-jemalloc-sys-bundling crates need their
    # bundled jemalloc compiled for 16 KiB pages, otherwise cache.nixos.org's
    # 4 KiB-built versions are pulled and abort here at runtime.
    nixpkgs.overlays = [
      (final: prev: {
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (pyFinal: pyPrev: {
            polars = pyPrev.polars.overridePythonAttrs (old: {
              env = (old.env or {}) // { JEMALLOC_SYS_WITH_LG_PAGE = "14"; };
            });
          })
        ];
      })
    ];

    networking = {
      hostName = "vivivi";
      useDHCP = lib.mkDefault true;
      firewall.allowedTCPPorts = [ 22 8080 ];
    };

    time.timeZone = "Europe/Lisbon";

    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "prohibit-password";
    };

    sops = {
      defaultSopsFile = "${self}/secrets/vivivi.yaml";
      age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      secrets = {
        atticd_env        = { restartUnits = [ "atticd.service" ]; };
        tailscale_authkey = { };
      };
    };

    services.tailscale = {
      enable = true;
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
    };

    # Attic binary cache server. Storage backend is IONOS S3; credentials and
    # JWT signing key live in the sops-encrypted atticd_env file (loaded as
    # systemd EnvironmentFile so settings can reference $-vars at runtime).
    services.atticd = {
      enable = true;
      environmentFile = config.sops.secrets.atticd_env.path;
      settings = {
        listen = "[::]:8080";

        chunking = {
          nar-size-threshold = 65536;
          min-size           = 16384;
          avg-size           = 65536;
          max-size           = 262144;
        };

        storage = {
          type     = "s3";
          bucket   = "nix-cache";
          # IONOS S3 endpoint — adjust region/endpoint when the bucket exists.
          # de bucket: https://s3-eu-central-1.ionoscloud.com (region "de")
          # eu-central-3 bucket: https://s3.eu-central-3.ionoscloud.com
          region   = "de";
          endpoint = "https://s3-eu-central-1.ionoscloud.com";
        };
      };
    };

    users.users.jcmfernandes = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      hashedPassword = "!";
      openssh.authorizedKeys.keys = jcmfernandesAuthorizedKeys;
    };

    users.users.root = {
      hashedPassword = "!";
      initialHashedPassword = lib.mkForce null;
      openssh.authorizedKeys.keys = jcmfernandesAuthorizedKeys;
    };

    security.sudo.wheelNeedsPassword = false;

    system.stateVersion = "25.11";
  };
}
