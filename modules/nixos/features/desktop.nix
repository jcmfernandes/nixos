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
    # for KMS screen capture on Wayland/niri. Tailnet-only: openFirewall stays
    # off and its ports (for the default base 47989) are opened solely on
    # tailscale0. Pair clients with a PIN via the web UI (https://karma:47990).
    services.sunshine = {
      enable = true;
      capSysAdmin = true;
      openFirewall = false;
      autoStart = true;
    };
    networking.firewall.interfaces.tailscale0 = {
      allowedTCPPorts = [ 47984 47989 47990 48010 ];
      allowedUDPPorts = [ 47998 47999 48000 48002 ];
    };

    security.polkit.enable = true;

    hardware = {
      enableAllFirmware = true;

      bluetooth.enable = true;
      bluetooth.powerOnBoot = true;

      graphics.enable = true;
    };
  };
}