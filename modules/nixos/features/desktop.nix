{self, ...}: {
  flake.nixosModules.desktop = {pkgs, ...}: let
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

    security.polkit.enable = true;

    # polkit.enable only starts the *daemon*. Actions defaulting to
    # auth_admin (e.g. udisks2's encrypted-unlock-system, which Nautilus hits
    # when unlocking an internal LUKS/LVM volume) additionally need a session
    # authentication agent to prompt for the password -- without one, polkit
    # denies outright ("no agent is available"). GNOME ships one via
    # gnome-shell; niri does not, so start it ourselves.
    systemd.user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome authentication agent";
      wantedBy = ["graphical-session.target"];
      wants = ["graphical-session.target"];
      after = ["graphical-session.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };

    hardware = {
      enableAllFirmware = true;

      bluetooth.enable = true;
      bluetooth.powerOnBoot = true;

      graphics.enable = true;
    };
  };
}
