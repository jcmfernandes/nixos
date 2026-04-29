{ self, inputs, ... }: {

  flake.nixosModules.moonConfiguration = { config, pkgs, lib, ... }: let
    jcmfernandesAuthorizedKeys = lib.filter (s: s != "")
      (lib.splitString "\n" (lib.fileContents inputs.jcmfernandes-keys));

    ntfyNotify = pkgs.writeShellApplication {
      name = "ntfy-notify";
      runtimeInputs = with pkgs; [ curl coreutils gawk ];
      text = ''
        set -eu
        subject=""
        while getopts 's:i:' opt; do
          case "$opt" in
            s) subject="$OPTARG" ;;
            i) : ;;
            *) : ;;
          esac
        done
        shift $((OPTIND - 1))

        body=$(cat)

        # If no -s (smartd mailer path), extract subject and body from RFC822-style input.
        if [ -z "$subject" ]; then
          subject=$(printf '%s\n' "$body" | awk -F': *' '/^Subject:/ {sub(/^Subject: */,""); print; exit}') || true
          body=$(printf '%s\n' "$body" | awk 'started {print} !started && /^$/ {started=1}')
        fi
        [ -z "$subject" ] && subject="moon alert"

        url=$(cat ${config.sops.secrets.ntfy_url.path})

        curl -fsS --max-time 10 --retry 3 --retry-delay 5 \
          -H "Title: $subject" \
          -H "Priority: high" \
          -H "Tags: warning" \
          --data-binary "$body" \
          "$url" >/dev/null
      '';
    };
  in {
    imports = (with inputs.nixos-raspberrypi.nixosModules; [
      raspberry-pi-5.base
      raspberry-pi-5.display-vc4
    ]) ++ [
      self.nixosModules.base
      self.nixosModules.general
      inputs.nixarr.nixosModules.default
      inputs.sops-nix.nixosModules.sops
    ];

    sops = {
      defaultSopsFile = "${self}/secrets/moon.yaml";
      age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      secrets = {
        luks_das_key = { };
        tailscale_authkey = { };
        restic_password = { };
        ntfy_url = { };
        caddy_env = { restartUnits = [ "caddy.service" ]; };
        njalla_ddns_env = { restartUnits = [ "njalla-ddns.service" ]; };
        restic_env = {
          restartUnits = [
            "restic-backups-immich.service"
            "restic-backups-state.service"
          ];
        };
        restic_immich_repo = { restartUnits = [ "restic-backups-immich.service" ]; };
        restic_state_repo  = { restartUnits = [ "restic-backups-state.service"  ]; };
      };
    };

    nixpkgs.overlays = let
      upstreamPkgs = import inputs.nixpkgs { system = pkgs.stdenv.hostPlatform.system; };
      unstablePkgs = import inputs.nixpkgs-unstable { system = pkgs.stdenv.hostPlatform.system; };
    in lib.mkAfter [
      (final: prev: {
        inherit (upstreamPkgs)
          ffmpeg ffmpeg-headless ffmpeg-full
          ffmpeg_7 ffmpeg_7-headless ffmpeg_7-full
          ffmpeg_8 ffmpeg_8-headless ffmpeg_8-full
          servarr-ffmpeg;
        inherit (unstablePkgs) mergerfs;
      })
    ];

    swapDevices = [{
      device = "/swapfile";
      size = 4096; # MB
    }];

    boot.kernel.sysctl."vm.overcommit_memory" = lib.mkForce "1";
    boot.kernel.sysctl."vm.swappiness" = 1;

    boot.loader.raspberry-pi.bootloader = "kernel";

    services.smartd = {
      enable = true;
      autodetect = false;
      defaults.monitored = "-a -d sat -o on -S on -n standby,q -s (S/../.././03|L/../../7/02) -W 4,40,50";
      devices = [
        { device = "/dev/disk/by-id/ata-ST2000DM008-2UB102_ZK20L15W"; }
        { device = "/dev/disk/by-id/ata-ST2000DM008-2UB102_ZK30LJ0R"; }
        { device = "/dev/disk/by-id/ata-ST2000DM008-2UB102_ZK20L42Q"; }
      ];
      notifications.mail = {
        enable = true;
        recipient = "root";
        mailer = "${ntfyNotify}/bin/ntfy-notify";
      };
    };

    systemd.services.disk-usage-alert = {
      description = "Alert via ntfy when any btrfs branch exceeds 80% usage";
      path = [ pkgs.coreutils pkgs.gawk ntfyNotify ];
      serviceConfig.Type = "oneshot";
      script = ''
        threshold=80
        for m in /mnt/disk1 /mnt/disk2 /mnt/disk3; do
          [ -d "$m" ] && mountpoint -q "$m" || continue
          pct=$(df -P "$m" | awk 'NR==2 {print $5}' | tr -d '%')
          if [ "$pct" -gt "$threshold" ]; then
            printf '%s is at %s%% usage (threshold %s%%)' "$m" "$pct" "$threshold" \
              | ntfy-notify -s "Disk usage alert: $m" root
          fi
        done
      '';
    };

    systemd.timers.disk-usage-alert = {
      description = "Periodic disk usage check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "15min";
        OnUnitActiveSec = "24h";
        Unit = "disk-usage-alert.service";
      };
    };

    systemd.services.hd-idle = {
      description = "Spin down idle USB disks";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 10;
        ExecStart = "${pkgs.hd-idle}/bin/hd-idle -i 0 -l /var/log/hd-idle.log"
          + " -a /dev/disk/by-id/ata-ST2000DM008-2UB102_ZK20L15W -i 600"
          + " -a /dev/disk/by-id/ata-ST2000DM008-2UB102_ZK30LJ0R -i 600"
          + " -a /dev/disk/by-id/ata-ST2000DM008-2UB102_ZK20L42Q -i 600";
      };
    };

    networking = {
      hostName = "moon";
      hostId = "cdbfae8b";
      # DNS:
      # - https://dns.sb
      # - https://joindns4.eu/for-public
      nameservers = [ "185.222.222.222" "2a09::" "86.54.11.100" "2a13:1001::86:54:11:100" ];
    };

    time.timeZone = "Europe/Lisbon";

    users.users.jcmfernandes = {
      isNormalUser = true;
      extraGroups = [ "wheel" "video" ];
      hashedPassword = "!";
      openssh.authorizedKeys.keys = jcmfernandesAuthorizedKeys;
    };

    users.users.root = {
      hashedPassword = "!";
      initialHashedPassword = lib.mkForce null;
      openssh.authorizedKeys.keys = jcmfernandesAuthorizedKeys;
    };

    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = [ pkgs.htop pkgs.fastfetch pkgs.mergerfs ];

    environment.etc."crypttab".text = ''
      data2 /dev/disk/by-id/ata-ST2000DM008-2UB102_ZK20L42Q-part1 /var/lib/luks-keys/das.key luks
      data3 /dev/disk/by-id/ata-ST2000DM008-2UB102_ZK30LJ0R-part1 /var/lib/luks-keys/das.key luks
    '';

    system.activationScripts.luksKey = lib.stringAfter [ "setupSecrets" ] ''
      install -d -m 700 -o root -g root /var/lib/luks-keys
      umask 277
      cp -f ${config.sops.secrets.luks_das_key.path} /var/lib/luks-keys/das.key.tmp
      mv -f /var/lib/luks-keys/das.key.tmp /var/lib/luks-keys/das.key
      chmod 400 /var/lib/luks-keys/das.key
    '';

    fileSystems."/mnt/disk2" = {
      device = "/dev/mapper/data2";
      fsType = "btrfs";
      options = [ "compress=zstd:3" "noatime" "nofail" ];
    };

    fileSystems."/mnt/disk3" = {
      device = "/dev/mapper/data3";
      fsType = "btrfs";
      options = [ "compress=zstd:3" "noatime" "nofail" ];
    };

    fileSystems."/data" = {
      device = "/mnt/disk2:/mnt/disk3";
      fsType = "fuse.mergerfs";
      options = [
        "defaults"
        "allow_other"
        "use_ino"
        "category.create=pfrd"
        "category.action=epall"
        "moveonenospc=true"
        "x-systemd.requires-mounts-for=/mnt/disk2"
        "x-systemd.requires-mounts-for=/mnt/disk3"
      ];
    };

    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "yes";
    };

    nixarr = {
      enable = true;
      stateDir = "/data/state/nixarr";
      mediaUsers = [ "nixos" ];
      plex.enable = true;
      sonarr.enable = true;
      radarr.enable = true;
      bazarr.enable = true;
      prowlarr.enable = true;
      audiobookshelf.enable = true;
      qbittorrent = {
        enable = true;
      };
      transmission = {
        enable = true;
        extraSettings = {
          port-forwarding-enabled = true;
          rpc-host-whitelist-enabled = false;
          incomplete-dir-enabled = false;
          rename-partial-files = false;
        };
      };
    };

    virtualisation.podman.enable = true;
    virtualisation.oci-containers = {
      backend = "podman";
      containers.byparr = {
        image = "ghcr.io/thephaseless/byparr:2.1.0@sha256:01a46a2865d9a6db5eb8ead04ec0dd33b8fbe233e8565ae70b50d4cc0af4cfb0";
        ports = [ "127.0.0.1:8191:8191" ];
        autoStart = true;
      };
      containers.profilarr = {
        image = "docker.io/santiagosayshey/profilarr:v1.1.4@sha256:8a514f8429cd33885166facc9eb6504fa9ded056c737609e5e8ef32ae0afb350";
        ports = [ "127.0.0.1:6868:6868" ];
        environment.TZ = config.time.timeZone;
        volumes = [ "/data/state/profilarr:/config" ];
        autoStart = true;
      };
    };

    services.immich = {
      enable = true;
      host = "127.0.0.1";
      mediaLocation = "/data/photos";
    };

    services.restic.backups.immich = {
      initialize = true;
      repositoryFile  = config.sops.secrets.restic_immich_repo.path;
      passwordFile    = config.sops.secrets.restic_password.path;
      environmentFile = config.sops.secrets.restic_env.path;
      paths = [
        "/data/photos"
        "/var/backup/immich-db.sql.gz"
      ];
      exclude = [
        "/data/photos/thumbs"
        "/data/photos/encoded-video"
      ];
      backupPrepareCommand = ''
        set -eu
        install -d -m 0700 -o root -g root /var/backup
        ${pkgs.util-linux}/bin/runuser -u immich -- \
          ${pkgs.postgresql}/bin/pg_dump --clean --if-exists immich \
          | ${pkgs.gzip}/bin/gzip -9 > /var/backup/immich-db.sql.gz
      '';
      timerConfig = {
        OnCalendar = "03:30";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
      pruneOpts = [
        "--keep-daily 14"
        "--keep-weekly 8"
        "--keep-monthly 24"
      ];
    };

    services.restic.backups.state = {
      initialize = true;
      repositoryFile  = config.sops.secrets.restic_state_repo.path;
      passwordFile    = config.sops.secrets.restic_password.path;
      environmentFile = config.sops.secrets.restic_env.path;
      paths = [
        "/data/state/nixarr"
        "/data/state/profilarr"
        "/var/backup/sonarr.db"
        "/var/backup/radarr.db"
        "/var/backup/prowlarr.db"
        "/var/backup/bazarr.db"
        "/var/backup/profilarr.db"
        "/var/lib/tailscale/tailscaled.state"
      ];
      exclude = [
        "/data/state/nixarr/plex/Plex Media Server/Cache"
        "/data/state/nixarr/plex/Plex Media Server/Logs"
        "/data/state/nixarr/plex/Plex Media Server/Crash Reports"
        "/data/state/nixarr/sonarr/sonarr.db"
        "/data/state/nixarr/sonarr/sonarr.db-shm"
        "/data/state/nixarr/sonarr/sonarr.db-wal"
        "/data/state/nixarr/radarr/radarr.db"
        "/data/state/nixarr/radarr/radarr.db-shm"
        "/data/state/nixarr/radarr/radarr.db-wal"
        "/data/state/nixarr/prowlarr/prowlarr.db"
        "/data/state/nixarr/prowlarr/prowlarr.db-shm"
        "/data/state/nixarr/prowlarr/prowlarr.db-wal"
        "/data/state/nixarr/bazarr/db/bazarr.db"
        "/data/state/nixarr/bazarr/db/bazarr.db-shm"
        "/data/state/nixarr/bazarr/db/bazarr.db-wal"
        "/data/state/profilarr/data/profilarr.db"
        "/data/state/profilarr/data/profilarr.db-shm"
        "/data/state/profilarr/data/profilarr.db-wal"
      ];
      backupPrepareCommand = ''
        set -eu
        install -d -m 0700 -o root -g root /var/backup
        for pair in \
          sonarr:/data/state/nixarr/sonarr/sonarr.db \
          radarr:/data/state/nixarr/radarr/radarr.db \
          prowlarr:/data/state/nixarr/prowlarr/prowlarr.db \
          bazarr:/data/state/nixarr/bazarr/db/bazarr.db \
          profilarr:/data/state/profilarr/data/profilarr.db; do
          name=''${pair%%:*}
          src=''${pair#*:}
          [ -f "$src" ] || continue
          ${pkgs.sqlite}/bin/sqlite3 "$src" ".backup /var/backup/$name.db"
        done
      '';
      timerConfig = {
        OnCalendar = "04:30";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
      ];
    };

    services.caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/njalla@v0.0.0-20250823094507-f709141f1fe6" ];
        hash = "sha256-rrOAR6noTDpV/I/hZXxhz0OXVJKu0mFQRq87RUrpmzw=";
      };
      environmentFile = config.sops.secrets.caddy_env.path;
      virtualHosts."*.moreirafernandes.com".extraConfig = ''
        tls {
          dns njalla {env.NJALLA_TOKEN}
        }

        @immich            host immich.moreirafernandes.com
        @plex              host plex.moreirafernandes.com
        @sonarr            host sonarr.moreirafernandes.com
        @radarr            host radarr.moreirafernandes.com
        @bazarr            host bazarr.moreirafernandes.com
        @prowlarr          host prowlarr.moreirafernandes.com
        @profilarr         host profilarr.moreirafernandes.com
        @audiobookshelf    host audiobookshelf.moreirafernandes.com
        @qbittorrent       host qbittorrent.moreirafernandes.com
        @transmission      host transmission.moreirafernandes.com

        handle @immich            { reverse_proxy 127.0.0.1:2283  }
        handle @plex              { reverse_proxy 127.0.0.1:32400 }
        handle @sonarr            { reverse_proxy 127.0.0.1:8989  }
        handle @radarr            { reverse_proxy 127.0.0.1:7878  }
        handle @bazarr            { reverse_proxy 127.0.0.1:6767  }
        handle @prowlarr          { reverse_proxy 127.0.0.1:9696  }
        handle @profilarr         { reverse_proxy 127.0.0.1:6868  }
        handle @audiobookshelf    { reverse_proxy 127.0.0.1:9292  }
        handle @qbittorrent       { reverse_proxy 127.0.0.1:5252  }
        handle @transmission      { reverse_proxy 127.0.0.1:9091  }

        handle { abort }
      '';
    };

    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      extraSetFlags = [
        "--advertise-routes=192.168.1.0/24"
        "--advertise-exit-node"
      ];
    };

    systemd.services.njalla-ddns = {
      description = "Update Njalla DDNS record for moon";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.iproute2 pkgs.jq pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = config.sops.secrets.njalla_ddns_env.path;
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
