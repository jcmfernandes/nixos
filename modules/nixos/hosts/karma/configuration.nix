{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.karmaConfiguration = {
    config,
    pkgs,
    ...
  }: {
    imports = [
      self.nixosModules.karmaHardware

      self.nixosModules.base
      self.nixosModules.nix
      self.nixosModules.persistenceDefaults
      self.nixosModules.desktop
      self.nixosModules.secureboot
      self.nixosModules.yubikey
      self.nixosModules.ups
      self.nixosModules.mise
      self.nixosModules.jcmfernandes

      # disko
      inputs.disko.nixosModules.disko
      self.diskoConfigurations.karma

      inputs.sops-nix.nixosModules.sops
      inputs.home-manager.nixosModules.home-manager
    ];

    sops = {
      defaultSopsFile = "${self}/secrets/karma.yaml";
      age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
      secrets = {
        tailscale_authkey = {};
        njalla_ddns_env = {restartUnits = ["njalla-ddns.service"];};
      };
    };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
    };

    nix.settings.experimental-features = ["nix-command" "flakes"];

    # Replace nixpkgs' niri with our fork's main-axis build. An overlay rather
    # than a `programs.niri.package` override so that *every* consumer picks it
    # up -- in particular the build-time `niri validate` step in the home
    # module, which would otherwise reject the `main-axis` option and fail the
    # rebuild.
    #
    # Uses niri's own prebuilt package rather than `inputs.niri.overlays.default`:
    # that overlay builds niri against *our* nixpkgs (26.05), but the fork's
    # `main-axis` branch needs `libdisplay-info_0_3`, which our 26.05 pin
    # doesn't have (only `libdisplay-info_0_2`). niri's own flake pins
    # nixpkgs-unstable, which does, so pulling its prebuilt package sidesteps
    # the mismatch entirely.
    nixpkgs.overlays = [
      (final: prev: {
        niri = inputs.niri.packages.${prev.stdenv.hostPlatform.system}.niri;
      })
    ];

    boot = {
      kernelParams = ["video=Virtual-1:1920x1080"];
      kernelPackages = pkgs.linuxPackages_latest;

      # Let unprivileged users bind from port 80 up (kernel default is 1024).
      # The same work dev stack that needs the mutable /etc/hosts below runs
      # its API gateway container on 80/443, and rootless podman binds those
      # as the invoking user -- without this the container never starts, which
      # in turn makes `podman-compose down` abort on the missing container.
      # Ports 1-79 (and their long tail of classic root-only daemons) stay
      # privileged, and nothing here is LAN-reachable anyway: the firewall
      # trusts tailscale0 only.
      kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 80;

      loader = {
        # UEFI-only: systemd-boot installs the removable ESP fallback
        # (EFI/BOOT/BOOTX64.EFI), so the disk boots after a VM->bare-metal
        # move without a machine-local NVRAM entry.
        systemd-boot.enable = true;
        systemd-boot.configurationLimit = 10;
        efi.canTouchEfiVariables = false;
      };
    };

    # 32 GiB swapfile. NixOS creates it with `btrfs filesystem mkswapfile`
    # (NOCOW, uncompressed) so swapon works on the btrfs root.
    swapDevices = [
      {
        device = "/swapfile";
        size = 32 * 1024; # MiB
      }
    ];

    networking = {
      hostName = "karma";
      networkmanager.enable = true;

      # Tailnet-only access, like vivivi. karma lives in a coworking space on
      # a hostile LAN, so nothing must be reachable from it: tailscale0 is the
      # only trusted interface, so SSH/etc. are reachable over the
      # tailnet while the LAN NIC stays fully closed. SSH's own firewall hole
      # is disabled below (services.openssh.openFirewall = false) so port 22
      # isn't opened on the LAN. Unlike vivivi there's no cloud security list
      # backing this up. The NixOS firewall is the only network layer (disk
      # is LUKS-encrypted; Secure Boot is staged via the secureboot module --
      # see this host's README to arm it).
      firewall.trustedInterfaces = ["tailscale0"];
    };

    # Ship /etc/hosts as a mutable copy instead of the default symlink into the
    # store: a work project's local dev stack uses `sudo hostctl add domains
    # ...` to point its service names at 127.0.0.1, and hostctl edits
    # /etc/hosts in place. NixOS's etc module only symlinks entries whose mode
    # is "symlink" (the default); any other mode makes it a root-owned copy
    # under /etc that root can write. Upstream's networking module sets only
    # `hosts.source`, so this needs no mkForce.
    #
    # Caveat: setup-etc.pl re-copies every non-symlink entry unconditionally on
    # each activation, so `nixos-rebuild switch` and every boot wipe whatever
    # hostctl wrote. Re-add the domains after a rebuild.
    environment.etc.hosts.mode = "0644";

    virtualisation.libvirtd.enable = true;
    programs.virt-manager.enable = true;
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings = {
        dns_enabled = true;
      };
    };

    # Silence the "Executing external compose provider ..." banner podman
    # prints on every `podman compose` / `docker compose` invocation. Handing
    # off to podman-compose is the intended setup here, so the notice is pure
    # noise on top of each command's output.
    virtualisation.containers.containersConf.settings.engine.compose_warning_logs = false;

    # Resolve unqualified image names against docker.io only. The NixOS default
    # is ["docker.io" "quay.io"], and with more than one candidate podman's
    # enforcing short-name mode stops to ask which registry to pull from --
    # once per image, so a compose file full of short names (redis:..,
    # postgres:.., neo4j:..) turns every cold start into a quiz. Images that
    # really do live elsewhere should carry their registry in the reference.
    virtualisation.containers.registries.search = ["docker.io"];

    # Trust the local mkcert development CA, so that the same work dev stack's
    # https://*.local endpoints verify. `mkcert -install` normally
    # appends the CA to the system trust store, but on NixOS /etc/ssl is
    # generated from the store and the install is silently lost, leaving
    # curl/OpenSSL to reject every request with "unable to get local issuer
    # certificate". Adding it here puts it in the generated
    # /etc/ssl/certs/ca-certificates.crt instead.
    #
    # Only the public certificate lives in this repo; the CA key stays in
    # ~/.local/share/mkcert/rootCA-key.pem. That key can mint a certificate for
    # *any* host this machine then trusts, so it must not leak -- an acceptable
    # trade on a single-user desktop, not on a shared box. Regenerating the CA
    # (`mkcert -uninstall`, or wiping that directory) invalidates the copy here:
    # re-copy rootCA.pem and rebuild.
    security.pki.certificateFiles = [./mkcert-rootCA.pem];

    services = {
      openssh.enable = true;
      # Don't punch port 22 in the LAN-facing firewall; SSH is reachable only
      # over the trusted tailscale0 interface (see networking.firewall above).
      openssh.openFirewall = false;
      flatpak.enable = true;
      udisks2.enable = true;
      printing.enable = true;
      tailscale = {
        enable = true;
        authKeyFile = config.sops.secrets.tailscale_authkey.path;
      };
    };

    # Publishes karma's tailscale IPv4 to njal.la as
    # karma.hosts.moreirafernandes.com. Mirrors vivivi's pattern: we don't
    # want the LAN/public IP in DNS, just the tailnet address.
    systemd.services.njalla-ddns = {
      description = "Update Njalla DDNS record for karma";
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
          "https://njal.la/update/?h=karma.hosts.moreirafernandes.com&k=$DDNS_KEY&a=$ts_ip&quiet"
      '';
    };

    systemd.timers.njalla-ddns = {
      description = "Periodic Njalla DDNS update for karma";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "5min";
        Unit = "njalla-ddns.service";
      };
    };

    programs = {
      appimage.enable = true;
      zsh.enable = true;
    };

    environment.systemPackages = with pkgs; [
      gcc
      git
      glib
      usbutils
    ];

    xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];
    xdg.portal.enable = true;

    # Pin GDM's Wayland greeter (mutter) to the DP-1 ultrawide. The greeter
    # draws the login form on the monitor flagged <primary>; without this it
    # picks one heuristically and can land on the rotated DP-2. mutter looks
    # up monitors.xml in the user config dir first and then, as a fallback,
    # in the XDG system config dirs (g_get_system_config_dirs) -- on karma
    # XDG_CONFIG_DIRS starts with /etc/xdg (pam_env seeds the greeter from
    # /etc/pam/environment). Delivering it at /etc/xdg/monitors.xml makes
    # every greeter session read it. A previous attempt dropped the file into
    # the greeter users' homes via tmpfiles, but that is a boot-time one-shot
    # while GDM's GdmDynUserStore creates and removes the greeter home under
    # /run/gdm/home/gdm-greeter{,-N} around each login, so the file did not
    # survive past the first login. The system path sidesteps the home
    # lifecycle entirely. niri ignores this file, so the user's own session
    # is unaffected. mutter only honours it if it matches the *full* set of
    # connected monitors by EDID spec (vendor PNP-id / product / serial,
    # captured live from `niri msg outputs` + the panels' EDID). DP-2 keeps
    # scale 1 here (not niri's 1.5): a fractional scale in monitors.xml needs
    # mutter's experimental fractional-scaling feature, and if it's off
    # mutter discards the whole file -- and DP-2 only shows a wallpaper
    # shield at the greeter, so its scale is cosmetic.
    environment.etc."xdg/monitors.xml".text = ''
      <monitors version="2">
        <configuration>
          <logicalmonitor>
            <x>0</x>
            <y>0</y>
            <scale>1</scale>
            <primary>yes</primary>
            <monitor>
              <monitorspec>
                <connector>DP-1</connector>
                <vendor>GSM</vendor>
                <product>38GN950</product>
                <serial>204NTQDD9340</serial>
              </monitorspec>
              <mode>
                <width>3840</width>
                <height>1600</height>
                <rate>143.998</rate>
              </mode>
            </monitor>
          </logicalmonitor>
          <logicalmonitor>
            <x>3840</x>
            <y>0</y>
            <scale>1</scale>
            <transform>
              <rotation>right</rotation>
            </transform>
            <monitor>
              <monitorspec>
                <connector>DP-2</connector>
                <vendor>BNQ</vendor>
                <product>BenQ RD280UG</product>
                <serial>EMF6T00067087</serial>
              </monitorspec>
              <mode>
                <width>3840</width>
                <height>2560</height>
                <rate>119.991</rate>
              </mode>
            </monitor>
          </logicalmonitor>
        </configuration>
      </monitors>
    '';

    users.users.root.hashedPassword = "!";

    # Unlike moon/vivivi, sudo requires a password here (the default). karma is
    # a GUI desktop on a hostile coworking LAN, so an unlocked session left
    # unattended must not grant instant root — the password keeps a session
    # compromise from immediately escalating.

    system.stateVersion = "25.11";
  };
}
