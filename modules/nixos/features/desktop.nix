_: {
  flake.nixosModules.desktop = {pkgs, ...}: {
    programs.niri = {
      enable = true;
      package = pkgs.niri;
      # Use xdg-desktop-portal-gtk rather than -gnome/Nautilus (the module's
      # default) for the file picker.
      useNautilus = false;
    };

    # xdg-desktop-portal-gnome 50 decides once, at startup, whether it is
    # running under a compatible compositor, by probing for mutter's
    # org.gnome.Mutter.ServiceChannel through a proxy built with
    # G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START. If the name has no owner it logs
    # "Non-compatible display server, exposing settings only" and then serves
    # *only* org.freedesktop.impl.portal.Settings for the rest of its life --
    # despite its gnome.portal file advertising ScreenCast, FileChooser and
    # the rest. Calls against those then fail with "No such interface", which
    # Firefox surfaces as an unactionable screen-sharing permissions message.
    #
    # The unit shipped by the package is ordered only After/Requisite/PartOf
    # graphical-session.target, which does not stop the portal frontend from
    # D-Bus-activating this backend while the compositor is torn down (it does
    # exactly that when closing orphaned sessions on logout). The backend then
    # starts with no compositor at all, latches "settings only", and -- having
    # been activated rather than started by the target -- survives into the
    # next session, where it is already poisoned.
    #
    # Tie it to niri instead. niri claims its D-Bus names in
    # DBusServers::start (a blocking zbus name request) strictly before it
    # signals READY to systemd, so "niri.service is active" implies the name
    # is owned: After= is a real guarantee here, not a timing bet.
    #
    # The other half needs two directives, deliberately *not* BindsTo=. BindsTo
    # propagates stop, but it is also a start dependency: a D-Bus activation of
    # this backend during teardown pulls niri.service back up, and a niri
    # started outside a logind session never becomes active (no DRM master,
    # black screen) while still blocking every later login, because
    # niri-session refuses to run when niri.service is already active. That is
    # the same resurrection the session units in homeModules avoid.
    #
    #   requisite = refuse activation outright while niri is down (the
    #               "cannot be activated at all" guarantee), without starting it.
    #   partOf    = stop/restart propagate from niri, so no poisoned instance
    #               outlives the session that created it.
    #
    # asDropin extends the packaged unit instead of replacing it.
    systemd.user.services.xdg-desktop-portal-gnome = {
      overrideStrategy = "asDropin";
      after = ["niri.service"];
      requisite = ["niri.service"];
      partOf = ["niri.service"];
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
