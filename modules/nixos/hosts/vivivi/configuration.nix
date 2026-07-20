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
      self.nixosModules.general
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
    # Flip this to point at the local attic once attic has been
    # bootstrapped and contains 16 KiB-built artifacts.
    nix.settings = {
      substitute = true;
      substituters = lib.mkForce [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = lib.mkForce [];
      require-sigs = true;
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
      attic-client
    ];

    # Idempotently provision the local attic cache. First boot: generates
    # an admin JWT (signed with the HS256 secret already in atticd_env),
    # writes /root/.config/attic/config.toml, and creates the
    # `aarch64-16kb` cache. Subsequent boots: token-refresh + cache-exists
    # check both no-op. After the first run, capture the cache's public
    # signing key with `attic cache info aarch64-16kb` and add it to
    # consumers' (moon's) `trusted-public-keys`. The pubkey is stable
    # across reboots as long as vivivi's disk isn't wiped — a fresh
    # install regenerates it server-side.
    systemd.services.attic-bootstrap = {
      description = "Idempotently provision the attic 'aarch64-16kb' cache";
      after = ["atticd.service"];
      wants = ["atticd.service"];
      wantedBy = ["multi-user.target"];
      path = [pkgs.attic-server pkgs.attic-client pkgs.curl];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        EnvironmentFile = config.sops.secrets.atticd_env.path;
      };
      script = ''
        set -euf
        SERVER=http://localhost:8080
        CACHE=aarch64-16kb
        CONFIG=/root/.config/attic/config.toml

        # Wait up to 60 s for atticd to answer.
        for _ in $(seq 1 60); do
          curl -sf --max-time 2 "$SERVER/_api/v1/health" >/dev/null && break
          sleep 1
        done

        if [ ! -f "$CONFIG" ]; then
          mkdir -p "$(dirname "$CONFIG")"
          token=$(atticadm make-token \
            --sub jcmfernandes --validity 5y \
            --pull '*' --push '*' --create-cache '*' \
            --configure-cache '*' --configure-cache-retention '*' \
            --destroy-cache '*')
          attic login local "$SERVER" "$token"
        fi

        if ! attic cache info "$CACHE" >/dev/null 2>&1; then
          attic cache create "$CACHE"
        fi

        attic use "local:$CACHE"
      '';
    };

    # Asynchronously push every new /nix/store path to the cache as
    # nix-daemon finalizes it. Depends on attic-bootstrap so it doesn't
    # try to push before the cache exists.
    systemd.services.attic-watch-store = {
      description = "Push new /nix/store paths to attic 'aarch64-16kb'";
      after = ["attic-bootstrap.service"];
      wants = ["attic-bootstrap.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.attic-client}/bin/attic watch-store aarch64-16kb";
        Restart = "always";
        RestartSec = 10;
        User = "root";
      };
    };

    # Safety net for watch-store: re-push the current system closure
    # daily. Attic dedupes by chunk hash, so anything already uploaded
    # costs only the metadata round-trip. Catches paths watch-store
    # missed (service restart mid-build, paths nix-copy'd in from
    # outside, or the closure that existed before watch-store first ran).
    systemd.services.attic-seed-current-system = {
      description = "Push current system closure to attic 'aarch64-16kb'";
      after = ["attic-bootstrap.service"];
      wants = ["attic-bootstrap.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.attic-client}/bin/attic push aarch64-16kb /run/current-system";
        User = "root";
      };
    };

    systemd.timers.attic-seed-current-system = {
      description = "Daily push of current system closure to attic";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "24h";
        Unit = "attic-seed-current-system.service";
        Persistent = true; # run on next boot if missed while powered off
      };
    };

    networking = {
      hostName = "vivivi";
      # useDHCP is set in hardware.nix
      # No ports open on the public NIC. Tailscale's UDP 41641 is opened
      # automatically by `services.tailscale.openFirewall` (default true),
      # and `tailscale0` is added to `firewall.trustedInterfaces` by the
      # same module — so sshd (22) and atticd (8080) remain reachable over
      # the tailnet but not from the open internet.
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
        atticd_env = {restartUnits = ["atticd.service"];};
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
          min-size = 16384;
          avg-size = 65536;
          max-size = 262144;
        };

        storage = {
          type = "s3";
          bucket = "moreirafernandesdotcom-nix-cache";
          region = "eu-central-3";
          endpoint = "https://s3.eu-central-3.ionoscloud.com";
        };
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
