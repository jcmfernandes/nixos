{self, ...}: {
  flake.nixosModules.desktop = {lib, pkgs, ...}: let
    selfpkgs = self.packages."${pkgs.stdenv.hostPlatform.system}";
  in {
    imports = [
      self.nixosModules.gtk

#     self.nixosModules.pipewire
      self.nixosModules.firefox
    ];

    programs.niri = {
      enable = true;
      package = selfpkgs.niri;
    };

    preferences.autostart = [selfpkgs.start-noctalia-shell];

    environment.systemPackages = [
      selfpkgs.terminal
      pkgs.nautilus
      selfpkgs.noctalia-shell
      pkgs.easyeffects
      pkgs.insync
      pkgs.vlc
      pkgs.unrar
      pkgs.file-roller
      pkgs.libreoffice
      pkgs.gimp
      pkgs.zathura
      pkgs.foliate
      pkgs.qbittorrent
      pkgs.gparted
      pkgs.wdisplays
      pkgs.celluloid
      pkgs.element-desktop
      pkgs.halloy
      pkgs.moonlight-qt
    ];

    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      ubuntu-sans
      cm_unicode
      corefonts
      unifont
    ];

    fonts.fontconfig.defaultFonts = {
      serif = ["Ubuntu Sans"];
      sansSerif = ["Ubuntu Sans"];
      monospace = ["JetBrainsMono Nerd Font"];
    };

    time.timeZone = "Europe/Lisbon";
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_ADDRESS = "pt_PT.UTF-8";
      LC_IDENTIFICATION = "pt_PT.UTF-8";
      LC_MEASUREMENT = "pt_PT.UTF-8";
      LC_MONETARY = "pt_PT.UTF-8";
      LC_NAME = "pt_PT.UTF-8";
      LC_NUMERIC = "pt_PT.UTF-8";
      LC_PAPER = "pt_PT.UTF-8";
      LC_TELEPHONE = "pt_PT.UTF-8";
      LC_TIME = "pt_PT.UTF-8";
    };

    services.displayManager.gdm.enable = true;
    services.displayManager.defaultSession = "niri";

    services.upower.enable = true;

    # gvfs backs Nautilus' trash, removable-drive mounting and network shares.
    services.gvfs.enable = true;

    # Sunshine: stream the desktop to Moonlight clients. capSysAdmin is needed
    # for KMS screen capture on Wayland/niri. openFirewall stays off and we
    # open no ports explicitly: Sunshine's TCP 47984/47989/47990/48010 and UDP
    # 47998-48002 are reachable only over the tailnet because tailscale0 is a
    # trusted interface (host-wide, set in karma's configuration.nix) while the
    # LAN is closed. Pair clients with a PIN via the web UI (https://karma:47990).
    services.sunshine = {
      enable = true;
      capSysAdmin = true;
      openFirewall = false;
      autoStart = true;
    };
    # Sunshine enables avahi with openFirewall = true to advertise itself for
    # Moonlight's mDNS discovery. On karma's hostile LAN we don't want an mDNS
    # responder answering, and mDNS doesn't traverse the tailnet anyway (no
    # multicast) — Moonlight connects to karma by hostname/IP. Close the hole.
    services.avahi.openFirewall = lib.mkForce false;
    # Sunshine sometimes loses a port-bind race at login (a stale instance from
    # the previous session can still hold RTSP 48010). On that fatal error it
    # exits 0, so the upstream unit's Restart=on-failure never fires and it
    # stays dead. "always" retries regardless of exit code (RestartSec=5s comes
    # from upstream) so it self-heals once the port frees — no manual start.
    # A controlled stop at logout (graphical-session.target teardown) is not a
    # restart trigger, so this won't fight session shutdown.
    systemd.user.services.sunshine.serviceConfig.Restart = lib.mkForce "always";

    security.polkit.enable = true;

    hardware = {
      enableAllFirmware = true;

      bluetooth.enable = true;
      bluetooth.powerOnBoot = true;

      graphics.enable = true;
    };
  };
}