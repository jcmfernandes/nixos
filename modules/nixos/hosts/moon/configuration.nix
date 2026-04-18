{ self, inputs, ... }: {

  flake.nixosModules.moonConfiguration = { config, pkgs, lib, ... }: {
    imports = (with inputs.nixos-raspberrypi.nixosModules; [
      raspberry-pi-5.base
      raspberry-pi-5.display-vc4
    ]) ++ [
      self.nixosModules.base
      self.nixosModules.general
      inputs.nixarr.nixosModules.default
    ];

    nixpkgs.overlays = let
      upstreamPkgs = import inputs.nixpkgs { system = pkgs.stdenv.hostPlatform.system; };
    in lib.mkAfter [
      (final: prev: {
        inherit (upstreamPkgs)
          ffmpeg ffmpeg-headless ffmpeg-full
          ffmpeg_7 ffmpeg_7-headless ffmpeg_7-full
          ffmpeg_8 ffmpeg_8-headless ffmpeg_8-full
          servarr-ffmpeg;
      })
    ];

    swapDevices = [{
      device = "/swapfile";
      size = 4096; # MB
    }];

    boot.kernel.sysctl."vm.overcommit_memory" = lib.mkForce "1";

    boot.loader.raspberry-pi.bootloader = "kernel";

    boot.supportedFilesystems = [ "zfs" ];
    boot.kernelParams = [ "zfs.zfs_arc_max=2147483648" ];
    services.zfs.autoScrub.enable = true;
    services.zfs.trim.enable = true;

    networking = {
      hostName = "moon";
      hostId = "cdbfae8b";
      # DNS:
      # - https://dns.sb
      # - https://joindns4.eu/for-public
      nameservers = [ "185.222.222.222" "2a09::" "86.54.11.100" "2a13:1001::86:54:11:100" ];
    };

    time.timeZone = "Europe/Lisbon";

    users.users.nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" "video" ];
      initialHashedPassword = "";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKswlDw7JPtBM7bX9yk4Cs3xMJMl3gQh40cKfNuvG4NM jcmfernandes@slashid-laptop"
      ];
    };

    users.users.root = {
      initialHashedPassword = "";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKswlDw7JPtBM7bX9yk4Cs3xMJMl3gQh40cKfNuvG4NM jcmfernandes@slashid-laptop"
      ];
    };

    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = [ pkgs.htop ];

    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "yes";
    };

    nixarr = {
      enable = true;
      mediaUsers = [ "nixos" ];
      plex.enable = true;
      sonarr.enable = true;
      bazarr.enable = true;
      prowlarr.enable = true;
      transmission = {
        enable = true;
        extraSettings = {
          port-forwarding-enabled = true;
          rpc-host-whitelist-enabled = false;
        };
      };
    };

    services.flaresolverr.enable = true;

    services.immich = {
      enable = true;
      host = "127.0.0.1";
      mediaLocation = "/data/photos";
    };

    services.caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/njalla@v0.0.0-20250823094507-f709141f1fe6" ];
        hash = "sha256-rrOAR6noTDpV/I/hZXxhz0OXVJKu0mFQRq87RUrpmzw=";
      };
      environmentFile = "/var/lib/njalla/caddy.env";
      virtualHosts."*.moreirafernandes.com".extraConfig = ''
        tls {
          dns njalla {env.NJALLA_TOKEN}
        }

        @immich       host immich.moreirafernandes.com
        @plex         host plex.moreirafernandes.com
        @sonarr       host sonarr.moreirafernandes.com
        @bazarr       host bazarr.moreirafernandes.com
        @prowlarr     host prowlarr.moreirafernandes.com
        @transmission host transmission.moreirafernandes.com

        handle @immich       { reverse_proxy 127.0.0.1:2283  }
        handle @plex         { reverse_proxy 127.0.0.1:32400 }
        handle @sonarr       { reverse_proxy 127.0.0.1:8989  }
        handle @bazarr       { reverse_proxy 127.0.0.1:6767  }
        handle @prowlarr     { reverse_proxy 127.0.0.1:9696  }
        handle @transmission { reverse_proxy 127.0.0.1:9091  }

        handle { abort }
      '';
    };

    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
      authKeyFile = "/var/lib/tailscale/authkey";
      extraSetFlags = [ "--advertise-routes=192.168.1.0/24" ];
    };

    systemd.services.njalla-ddns = {
      description = "Update Njalla DDNS record for moon";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.iproute2 pkgs.jq pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = "/var/lib/njalla/ddns.env";
        DynamicUser = true;
      };
      script = ''
        lan_ip=$(ip -4 -j route get 1.1.1.1 | jq -r '.[0].prefsrc')
        if [ -z "$lan_ip" ] || [ "$lan_ip" = "null" ]; then
          echo "Could not determine LAN IP" >&2
          exit 1
        fi
        curl -fsS --max-time 15 --retry 3 --retry-delay 5 \
          "https://njal.la/update/?h=moon.hosts.moreirafernandes.com&k=$DDNS_KEY&a=$lan_ip&quiet"
      '';
    };

    systemd.timers.njalla-ddns = {
      description = "Periodic Njalla DDNS update for moon";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "5min";
        Unit = "njalla-ddns.service";
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];

    systemd.tmpfiles.rules = [
      "d /data        0755 root   root   - -"
      "d /data/photos 0700 immich immich - -"
    ];

    system.stateVersion = config.system.nixos.release;
  };

}
