{ self, inputs, ... }: {

  flake.nixosModules.moonConfiguration = { config, pkgs, lib, ... }: let
    jcmfernandesAuthorizedKeys = lib.filter (s: s != "")
      (lib.splitString "\n" (lib.fileContents inputs.jcmfernandes-keys));

    # Shared source of truth for the subdomains Caddy fronts on moon. The
    # opentofu/infra stack reads the same file to provision matching CNAME
    # records at Njalla — add/remove entries here and both apply.
    domains = builtins.fromJSON (builtins.readFile ./domains.json);
    apex = "moreirafernandes.com";

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
    imports = [
      self.nixosModules.moonHardware
      self.nixosModules.moonOverlays
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
        nix_remote_builder_key = { };
      };
    };

    # Offload builds to vivivi (OCI aarch64, 16 KiB pages — matches moon's
    # ABI exactly). ssh-ng over the tailnet, authenticated with a dedicated
    # ed25519 key whose private half lives in sops; vivivi's host pubkey is
    # pinned in programs.ssh.knownHosts so the daemon never prompts.
    nix.distributedBuilds = true;
    nix.settings.max-jobs = 0;
    nix.buildMachines = [{
      hostName = "vivivi";
      systems = [ "aarch64-linux" ];
      protocol = "ssh-ng";
      sshUser = "nix-ssh";
      sshKey = config.sops.secrets.nix_remote_builder_key.path;
      maxJobs = 4;
      speedFactor = 4;
      supportedFeatures = [ "kvm" "big-parallel" "nixos-test" "benchmark" ];
    }];

    programs.ssh.knownHosts.vivivi = {
      hostNames = [ "vivivi" "vivivi.hosts.moreirafernandes.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuy8a/EmZC+gegkKUOZBA3MQeAZwEzaUBjig/gVQhvC root@vivivi";
    };

    # nixpkgs.overlays: see moonOverlays.

    # smartd.devices, sysctl, bootloader: see moonHardware.
    services.smartd = {
      enable = true;
      autodetect = false;
      defaults.monitored = "-a -d sat -o on -S on -n standby,q -s (S/../.././03|L/../../7/02) -W 4,40,50";
      notifications.mail = {
        enable = true;
        recipient = "root";
        mailer = "${ntfyNotify}/bin/ntfy-notify";
      };
    };

    # smartd's long self-test only checks drive media; btrfs scrub checks
    # filesystem data via checksums — the only thing that catches bit-rot.
    services.btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      fileSystems = [ "/mnt/disk1" "/mnt/disk2" "/mnt/disk3" ];
    };

    # btrfs-scrub-*.service only "fails" if the scrub command errors. If it
    # completes but finds corrupted/uncorrectable extents, that's logged but
    # the unit succeeds — so we post-check status and ntfy on any nonzero
    # error count. Triggered after the scheduled scrub finishes.
    systemd.services.btrfs-scrub-report = {
      description = "Report btrfs scrub errors to ntfy";
      path = [ pkgs.btrfs-progs pkgs.coreutils pkgs.gawk ntfyNotify ];
      serviceConfig.Type = "oneshot";
      script = ''
        for m in /mnt/disk1 /mnt/disk2 /mnt/disk3; do
          mountpoint -q "$m" || continue
          status=$(btrfs scrub status -R "$m" 2>/dev/null || true)
          errs=$(printf '%s\n' "$status" \
            | awk -F: '/_errors:/ {gsub(/ /,"",$2); sum+=$2} END {print sum+0}')
          if [ "$errs" -gt 0 ]; then
            printf '%s\n\n%s\n' "$m reported $errs scrub error(s)." "$status" \
              | ntfy-notify -s "btrfs scrub errors: $m" root
          fi
        done
      '';
    };

    systemd.timers.btrfs-scrub-report = {
      description = "Check btrfs scrub results after monthly scrub";
      wantedBy = [ "timers.target" ];
      # autoScrub fires at the monthly tick (1st 00:00); scrub of three ~370G
      # SMR disks finishes in well under a day. Inspect status on the 2nd.
      timerConfig = {
        OnCalendar = "*-*-02 03:00:00";
        Persistent = true;
        Unit = "btrfs-scrub-report.service";
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

    # hd-idle systemd unit: see moonHardware.

    networking = {
      hostName = "moon";
      # hostId is set in hardware.nix
      # DNS:
      # - https://dns.sb
      # - https://joindns4.eu/for-public
      nameservers = [ "185.222.222.222" "2a09::" "86.54.11.100" "2a13:1001::86:54:11:100" ];
    };

    time.timeZone = "Europe/Lisbon";

    # Keep the journal in RAM, capped so it can't pressure the /run tmpfs.
    services.journald = {
      storage = "volatile";
      extraConfig = "RuntimeMaxUse=128M";
    };

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

    environment.systemPackages = with pkgs; [
      htop
      fastfetch
      mergerfs
      smartmontools
    ];

    # crypttab generated in hardware.nix from the disks attrset.

    system.activationScripts.luksKey = lib.stringAfter [ "setupSecrets" ] ''
      install -d -m 700 -o root -g root /var/lib/luks-keys
      umask 277
      cp -f ${config.sops.secrets.luks_das_key.path} /var/lib/luks-keys/das.key.tmp
      mv -f /var/lib/luks-keys/das.key.tmp /var/lib/luks-keys/das.key
      chmod 400 /var/lib/luks-keys/das.key
    '';

    fileSystems."/mnt/disk1" = {
      device = "/dev/mapper/data1";
      fsType = "btrfs";
      options = [ "compress=zstd:3" "noatime" "nofail" ];
    };

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
      device = "/mnt/disk1:/mnt/disk2:/mnt/disk3";
      fsType = "fuse.mergerfs";
      options = [
        "defaults"
        "allow_other"
        "use_ino"
        "category.create=pfrd"
        "category.action=epall"
        "moveonenospc=true"
        "x-systemd.requires-mounts-for=/mnt/disk1"
        "x-systemd.requires-mounts-for=/mnt/disk2"
        "x-systemd.requires-mounts-for=/mnt/disk3"
      ];
    };

    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "yes";
      hostKeys = [
        { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
      ];
    };

    nixarr = {
      enable = true;
      stateDir = "/state/nixarr";
      mediaUsers = [ "nixos" ];
      plex.enable = true;
      sonarr.enable = true;
      radarr.enable = true;
      bazarr.enable = true;
      prowlarr.enable = true;
      audiobookshelf.enable = true;
      shelfmark.enable = true;
      seerr.enable = true;
      qbittorrent = {
        enable = true;
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
        volumes = [ "/state/profilarr:/config" ];
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
        "/state/nixarr"
        "/state/profilarr"
        "/var/backup/sonarr.db"
        "/var/backup/radarr.db"
        "/var/backup/prowlarr.db"
        "/var/backup/bazarr.db"
        "/var/backup/profilarr.db"
        "/var/backup/shelfmark.db"
        "/var/backup/seerr.db"
        "/var/lib/tailscale/tailscaled.state"
      ];
      exclude = [
        "/state/nixarr/plex/Plex Media Server/Cache"
        "/state/nixarr/plex/Plex Media Server/Logs"
        "/state/nixarr/plex/Plex Media Server/Crash Reports"
        "/state/nixarr/sonarr/sonarr.db"
        "/state/nixarr/sonarr/sonarr.db-shm"
        "/state/nixarr/sonarr/sonarr.db-wal"
        "/state/nixarr/radarr/radarr.db"
        "/state/nixarr/radarr/radarr.db-shm"
        "/state/nixarr/radarr/radarr.db-wal"
        "/state/nixarr/prowlarr/prowlarr.db"
        "/state/nixarr/prowlarr/prowlarr.db-shm"
        "/state/nixarr/prowlarr/prowlarr.db-wal"
        "/state/nixarr/bazarr/db/bazarr.db"
        "/state/nixarr/bazarr/db/bazarr.db-shm"
        "/state/nixarr/bazarr/db/bazarr.db-wal"
        "/state/nixarr/shelfmark/users.db"
        "/state/nixarr/shelfmark/users.db-shm"
        "/state/nixarr/shelfmark/users.db-wal"
        "/state/nixarr/seerr/db/db.sqlite3"
        "/state/nixarr/seerr/db/db.sqlite3-shm"
        "/state/nixarr/seerr/db/db.sqlite3-wal"
        "/state/profilarr/data/profilarr.db"
        "/state/profilarr/data/profilarr.db-shm"
        "/state/profilarr/data/profilarr.db-wal"
      ];
      backupPrepareCommand = ''
        set -eu
        install -d -m 0700 -o root -g root /var/backup
        for pair in \
          sonarr:/state/nixarr/sonarr/sonarr.db \
          radarr:/state/nixarr/radarr/radarr.db \
          prowlarr:/state/nixarr/prowlarr/prowlarr.db \
          bazarr:/state/nixarr/bazarr/db/bazarr.db \
          shelfmark:/state/nixarr/shelfmark/users.db \
          seerr:/state/nixarr/seerr/db/db.sqlite3 \
          profilarr:/state/profilarr/data/profilarr.db; do
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
        hash = "sha256-kWYIptO4AAsSlvyC2GGnBw/2DBBoYQ0SfPo6dbrC5DQ=";
      };
      environmentFile = config.sops.secrets.caddy_env.path;
      virtualHosts."*.${apex}".extraConfig = let
        matchers = lib.concatStringsSep "\n        "
          (lib.mapAttrsToList (name: _: "@${name} host ${name}.${apex}") domains);
        handlers = lib.concatStringsSep "\n        "
          (lib.mapAttrsToList
            (name: cfg: "handle @${name} { reverse_proxy 127.0.0.1:${toString cfg.port} }")
            domains);
      in ''
        tls {
          dns njalla {env.NJALLA_TOKEN}
        }

        ${matchers}

        ${handlers}

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

    networking.firewall.allowedTCPPorts = [ 80 443 32400 ];
    networking.firewall.allowedUDPPorts = [ 32410 32412 32413 32414 ];

    systemd.tmpfiles.rules = [
      "d /data        0755 root   root   - -"
      "d /data/photos 0700 immich immich - -"
    ];

    system.stateVersion = config.system.nixos.release;
  };

}
