{
  flake.homeModules.insync = {pkgs, ...}: {
    home.packages = [pkgs.insync];

    # Insync as a systemd user service so the sync daemon comes up with the
    # session instead of being started by hand. Its own unit (and cgroup)
    # keeps it clear of noctalia's, which home-manager activation restarts on
    # every switch -- the same reasoning as homeModules.emacs' daemon.
    systemd.user.services.insync = {
      Unit = {
        Description = "Insync (Google Drive sync)";
        # Insync is a Qt GUI app that lives in the tray, so it needs a live
        # Wayland socket. niri is a Type=notify user service that signals
        # readiness once its socket is bound (same pattern as
        # homeModules.noctalia's ordering). noctalia owns the
        # StatusNotifierWatcher, so starting after it means the tray icon
        # registers on the first try rather than after a retry.
        #
        # Requisite, not Requires: Requires would let this unit's own
        # Restart=on-failure *pull niri up* after a session teardown (insync
        # coredumps when the Wayland socket vanishes), and a niri started
        # outside a logind session never becomes active while still blocking
        # every subsequent login. Requisite fails fast instead.
        #
        # After=graphical-session.target is what keeps this out of an ordering
        # cycle: the target implicitly orders itself after the units it Wants,
        # so ordering after noctalia -- which upstream orders after the target
        # -- would otherwise close the loop target -> insync -> noctalia ->
        # target. An explicit ordering to the target suppresses the implicit
        # one, putting insync on noctalia's side of it.
        After = ["graphical-session.target" "niri.service" "noctalia.service"];
        Requisite = ["niri.service"];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        Type = "simple";
        # `insync start` forks and detaches by default, which systemd would
        # read as the service exiting; --no-daemon keeps it in the foreground.
        ExecStart = "${pkgs.insync}/bin/insync start --no-daemon";
        ExecStop = "${pkgs.insync}/bin/insync quit";
        Restart = "on-failure";
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}
