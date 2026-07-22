{inputs, ...}: {
  flake.homeModules.noctalia = {pkgs, ...}: {
    imports = [inputs.noctalia.homeModules.default];

    # Order the bar after the compositor is genuinely ready, fixing "fatal:
    # failed to connect to Wayland display" at the source. niri runs as a
    # Type=notify user service (niri.service) that signals readiness only
    # once its Wayland socket is bound, so After+Requires gate noctalia on a
    # live socket. The generated unit's After=graphical-session.target is
    # not enough on its own: systemd ordering only holds within a shared
    # start transaction, so a lone restart (home-manager activation runs
    # `systemctl --user restart noctalia` on switch) could still start the
    # bar before niri was up and burn through its restart limit.
    systemd.user.services.noctalia.Unit = {
      After = ["niri.service"];
      Requires = ["niri.service"];
    };

    # Noctalia v5 (the native C++ rewrite) is configured via TOML in
    # ~/.config/noctalia/. Upstream's hm module generates config.toml from
    # `settings` and validates it at build time, so a schema mismatch fails
    # the build instead of booting an unconfigured shell. Only deliberate
    # deviations from upstream defaults belong here.
    programs.noctalia = {
      enable = true;
      package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
      # Run as a user service (graphical-session.target); restarts
      # automatically when the generated config changes.
      systemd.enable = true;
      settings = {
        theme = {
          mode = "dark";
          source = "builtin";
          builtin = "Gruvbox";
        };
        bar.main.position = "left";
        # Wallpaper is handled by awww (see homeModules.niri).
        wallpaper.enabled = false;
        # Lock after 5 minutes of inactivity; desktop, so no idle
        # screen-off/suspend behaviors beyond that.
        idle.behavior.lock = {
          enabled = true;
          timeout = 300;
          action = "lock";
        };
      };
    };
  };
}
