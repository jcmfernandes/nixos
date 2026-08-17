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
        After = ["niri.service" "noctalia.service"];
        Requires = ["niri.service"];
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
