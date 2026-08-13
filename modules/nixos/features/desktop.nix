_: {
  flake.nixosModules.desktop = {
    lib,
    pkgs,
    ...
  }: let
    # xdg-desktop-portal-gnome 50 probes for mutter's
    # org.gnome.Mutter.ServiceChannel exactly once, at startup, through a
    # proxy built with G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START. niri does claim
    # that name, but only shortly *after* it signals readiness -- so any
    # start of the portal that wins that race logs "Non-compatible display
    # server, exposing settings only" and then serves *only* the Settings
    # interface for the rest of the session, even though its gnome.portal
    # file advertises FileChooser, ScreenCast and the rest. Screen sharing
    # then fails with "No such interface
    # org.freedesktop.impl.portal.ScreenCast" and file dialogs with the
    # FileChooser equivalent. Hold the portal back until the name is owned.
    wait-for-mutter-service-channel = pkgs.writeShellApplication {
      name = "wait-for-mutter-service-channel";
      runtimeInputs = [pkgs.systemd pkgs.coreutils];
      text = ''
        for _ in $(seq 100); do
          if [ "$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
                    org.freedesktop.DBus NameHasOwner s \
                    org.gnome.Mutter.ServiceChannel)" = "b true" ]; then
            exit 0
          fi
          sleep 0.1
        done
        echo "org.gnome.Mutter.ServiceChannel never appeared; starting anyway" >&2
      '';
    };
  in {
    programs.niri = {
      enable = true;
      package = pkgs.niri;
      # Use xdg-desktop-portal-gtk rather than -gnome/Nautilus (the module's
      # default) for the file picker.
      useNautilus = false;
    };

    # See wait-for-mutter-service-channel above. asDropin so this extends the
    # unit shipped by the xdg-desktop-portal-gnome package instead of
    # replacing it.
    systemd.user.services.xdg-desktop-portal-gnome = {
      overrideStrategy = "asDropin";
      serviceConfig.ExecStartPre = lib.getExe wait-for-mutter-service-channel;
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

    # The dconf daemon; hm's gtk/dconf settings need it (previously enabled
    # inside the gtk feature module).
    programs.dconf.enable = true;

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
