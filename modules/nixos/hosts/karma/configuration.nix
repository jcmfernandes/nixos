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

    boot = {
      kernelParams = ["video=Virtual-1:1920x1080"];
      kernelPackages = pkgs.linuxPackages_latest;
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

    virtualisation.libvirtd.enable = true;
    programs.virt-manager.enable = true;
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings = {
        dns_enabled = true;
      };
    };

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
    ];

    xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];
    xdg.portal.enable = true;

    # Pin GDM's Wayland greeter (mutter) to the DP-1 ultrawide. The greeter
    # draws the login form on the monitor flagged <primary>; without this it
    # picks one heuristically and can land on the rotated DP-2. mutter reads
    # this from $HOME/.config/monitors.xml. On GDM 50 the greeter runs as one
    # of the dynamic `gdm-greeter{,-N}` users (home /run/gdm/home/gdm-greeter
    # {,-N}), NOT as `gdm` (home /run/gdm), so the file must land in each
    # greeter user's home -- the user pool and .config ownership mirror
    # nixpkgs' gdm module (services/display-managers/gdm.nix). We create the
    # .config dir ourselves too: that module only seeds it when pulseaudio is
    # enabled, and karma uses pipewire. mutter only honours the file if it
    # matches the *full* set of connected monitors by EDID spec (vendor
    # PNP-id / product / serial, captured live from `niri msg outputs` + the
    # panels' EDID). DP-2 keeps scale 1 here (not niri's 1.5): a fractional
    # scale in monitors.xml needs mutter's experimental fractional-scaling
    # feature, and if it's off mutter discards the whole file -- and DP-2 only
    # shows a wallpaper shield at the greeter, so its scale is cosmetic.
    systemd.tmpfiles.rules = let
      gdmMonitors = pkgs.writeText "gdm-monitors.xml" ''
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
      # GDM assigns the greeter session one of these five dynamic users per
      # seat; place the config in every one so whichever it picks reads it.
      greeters = ["gdm-greeter" "gdm-greeter-2" "gdm-greeter-3" "gdm-greeter-4" "gdm-greeter-5"];
    in
      builtins.concatMap (u: [
        "d /run/gdm/home/${u}/.config 0711 ${u} gdm"
        "L+ /run/gdm/home/${u}/.config/monitors.xml - - - - ${gdmMonitors}"
      ])
      greeters;

    users.users.root.hashedPassword = "!";

    # Unlike moon/vivivi, sudo requires a password here (the default). karma is
    # a GUI desktop on a hostile coworking LAN, so an unlocked session left
    # unattended must not grant instant root — the password keeps a session
    # compromise from immediately escalating.

    system.stateVersion = "25.11";
  };
}
