{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.karmaConfiguration = {
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
      self.nixosModules.karmaHardware

      self.nixosModules.base
      self.nixosModules.nix
      self.nixosModules.persistenceDefaults
      self.nixosModules.desktop
      self.nixosModules.secureboot
      self.nixosModules.yubikey
      self.nixosModules.mise

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
      users.jcmfernandes = {
        imports = [
          self.homeModules.yubikey-ssh
          self.homeModules.git
          self.homeModules.noctalia
          self.homeModules.shell
          self.homeModules.which-key
          self.homeModules.kitty
          self.homeModules.niri
          self.homeModules.gtk
          self.homeModules.desktop-apps
          self.homeModules.fonts
          self.homeModules.flatpak
          self.homeModules.firefox
          self.homeModules.emacs
        ];
        home.stateVersion = "25.11";
      };
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
      git
      glib
    ];

    xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];
    xdg.portal.enable = true;

    users.users.jcmfernandes = {
      isNormalUser = true;
      shell = pkgs.zsh;
      extraGroups = ["wheel" "networkmanager" "input" "uinput" "video" "render" "libvirtd"];
      hashedPassword = "$6$mTNpK1zBZ9ksDGWA$vtotYvcTAeu3J8ZJAB6LSlVxPu9L.FCNI16eTfrvVv7wjc7FuBqvccE4hYzW9hr/pf1oHyhQxs7UEV.wRww4L1";
      # Shared key list (includes the YubiKey PIV key), matching moon/vivivi.
      openssh.authorizedKeys.keys = jcmfernandesAuthorizedKeys;
    };

    users.users.root.hashedPassword = "!";

    # Unlike moon/vivivi, sudo requires a password here (the default). karma is
    # a GUI desktop on a hostile coworking LAN, so an unlocked session left
    # unattended must not grant instant root — the password keeps a session
    # compromise from immediately escalating.

    system.stateVersion = "25.11";
  };
}
