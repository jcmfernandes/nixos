{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.viviviConfiguration = {
    config,
    pkgs,
    lib,
    ...
  }: let
    jcmfernandesAuthorizedKeys =
      lib.filter (s: s != "")
      (lib.splitString "\n" (lib.fileContents inputs.jcmfernandes-keys));
  in {
    imports = [
      self.nixosModules.viviviHardware
      self.nixosModules.base
      self.nixosModules.nix
      self.nixosModules.persistenceDefaults
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      self.diskoConfigurations.vivivi
    ];

    # vivivi rides nixos-unstable (see hosts/vivivi/default.nix) so
    # linuxPackages_latest is already the channel's freshest kernel.
    boot.kernelPackages = pkgs.linuxPackages_latest;

    # 16 KiB pages so binaries built here run natively on moon.
    boot.kernelPatches = [
      {
        name = "arm64-16k-pages";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          ARM64_16K_PAGES = yes;
          ARM64_4K_PAGES = lib.mkForce no;
          ARM64_64K_PAGES = lib.mkForce no;
        };
      }
    ];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Every built output that ends up on vivivi must be compiled natively
    # here so the closure is consistent with the 16 KiB-page kernel — but
    # we still want sources (fixed-output derivations) substituted from
    # cache.nixos.org, otherwise every fetchurl bottlenecks on flaky
    # upstream mirrors. The trick is to list a substituter but trust no
    # signing keys: FODs are content-addressable so the hash check
    # suffices, while built derivations require a trusted signature
    # (which they no longer have) and therefore rebuild locally.
    nix.settings = {
      substitute = true;
      substituters = lib.mkForce [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = lib.mkForce [];
      require-sigs = true;

      # 4 vCPUs. The defaults (max-jobs = auto = 4, cores = 0 = all 4) let
      # 16 build threads compete for 4 cores, which drove load averages of
      # 15-20 and made timing-sensitive test suites lose their races --
      # gnulib's test-lock hit its own alarm, paho-mqtt's fake-broker tests
      # missed late callbacks. Since everything that lands here is built
      # from source (see above), that contention is the normal state, not a
      # rare spike. 2 jobs x 2 cores keeps the box fully busy without
      # oversubscribing it.
      max-jobs = 2;
      cores = 2;
    };

    # Same workaround as moon: tikv-jemalloc-sys-bundling crates need their
    # bundled jemalloc compiled for 16 KiB pages, otherwise cache.nixos.org's
    # 4 KiB-built versions are pulled and abort here at runtime.
    nixpkgs.overlays = [
      (final: prev: {
        pythonPackagesExtensions =
          prev.pythonPackagesExtensions
          ++ [
            (pyFinal: pyPrev: {
              polars = pyPrev.polars.overridePythonAttrs (old: {
                env = (old.env or {}) // {JEMALLOC_SYS_WITH_LG_PAGE = "14";};
              });
            })
          ];
      })
    ];

    environment.systemPackages = with pkgs; [
      fastfetch
    ];

    networking = {
      hostName = "vivivi";
      # useDHCP is set in hardware.nix
      # No ports open on the public NIC. Tailscale's UDP 41641 is opened
      # automatically by `services.tailscale.openFirewall` (default true),
      # and `tailscale0` is added to `firewall.trustedInterfaces` by the
      # same module -- so sshd (22) remains reachable over the tailnet but
      # not from the open internet.
      firewall.allowedTCPPorts = [];
    };

    time.timeZone = "Europe/Lisbon";

    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "prohibit-password";
      hostKeys = [
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
      ];
    };

    sops = {
      defaultSopsFile = "${self}/secrets/vivivi.yaml";
      age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
      secrets = {
        tailscale_authkey = {};
        njalla_ddns_env = {};
      };
    };

    services.tailscale = {
      enable = true;
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
    };

    # Publishes vivivi's tailscale IPv4 to njal.la as
    # vivivi.hosts.moreirafernandes.com. Public IP would be wrong: the OCI
    # firewall blocks everything except WireGuard UDP, so DNS pointing
    # there would mislead clients. Tailnet members get the right address;
    # non-tailnet clients resolve to an unroutable 100.x.x.x, which is the
    # intended security posture.
    systemd.services.njalla-ddns = {
      description = "Update Njalla DDNS record for vivivi";
      after = ["network-online.target" "tailscaled.service"];
      wants = ["network-online.target" "tailscaled.service"];
      path = [config.services.tailscale.package pkgs.curl];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = config.sops.secrets.njalla_ddns_env.path;
      };
      script = ''
        ts_ip=$(tailscale ip -4 | head -n1)
        if [ -z "$ts_ip" ]; then
          echo "Could not determine tailscale IP" >&2
          exit 1
        fi
        curl -fsS --max-time 15 --retry 3 --retry-delay 5 \
          "https://njal.la/update/?h=vivivi.hosts.moreirafernandes.com&k=$DDNS_KEY&a=$ts_ip&quiet"
      '';
    };

    systemd.timers.njalla-ddns = {
      description = "Periodic Njalla DDNS update for vivivi";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "5min";
        Unit = "njalla-ddns.service";
      };
    };

    # Remote-build SSH user used by moon's nix-daemon. Trusted so it can
    # import paths and trigger builds without sudo. Authorized key is
    # paired with moon's sops-encrypted nix_remote_builder_key.
    users.users.nix-ssh = {
      isNormalUser = true;
      description = "Nix remote build user";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEzh8uavBf8IhXbddXGoWzr2GL0GUD4hDa5XFlbFT5qz nix-builder@moon"
      ];
    };

    nix.settings.trusted-users = ["nix-ssh"];

    users.users.jcmfernandes = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      # SHA-512 crypt of "password12345!" — set for serial-console
      # diagnostics. Rotate or set back to "!" once vivivi is healthy.
      hashedPassword = "$6$bl41SF7xj6VGxe7M$PA12whvo7YqLuZUFl9YZ39Hk78b/Vf6olmaDUprbyl3/RaBGJGZRkFA9FTxjHwPaSLOvnvsZ4J.2Bfd6CMYQ60";
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
