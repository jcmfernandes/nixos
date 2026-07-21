{inputs, ...}: {
  flake.homeModules.noctalia = {pkgs, ...}: {
    imports = [inputs.noctalia.homeModules.default];

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
        # Wallpaper is handled by awww (see the niri wrapper).
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
