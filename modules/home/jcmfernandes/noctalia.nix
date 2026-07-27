{inputs, ...}: {
  flake.homeModules.noctalia = {pkgs, ...}: let
    # Left-click action for the UPS bar button: pop a desktop notification
    # with the UPS's current charge/status/load. Noctalia v5's custom_button
    # is static (no live glyph/tooltip), so this is the on-demand way to read
    # the charge from the bar; live state-change alerts come from
    # homeModules.upsIndicator.
    ups-status-notify = pkgs.writeShellApplication {
      name = "ups-status-notify";
      runtimeInputs = [pkgs.nut pkgs.libnotify];
      text = ''
        data="$(upsc evo 2>/dev/null || true)"
        get() { printf '%s\n' "$data" | sed -n "s/^$1: //p"; }

        status="$(get ups.status)"
        if [ -z "$status" ]; then
          notify-send -a "UPS" -u critical "UPS unreachable" "No response from upsd." || true
          exit 0
        fi

        charge="$(get battery.charge)"
        load="$(get ups.load)"
        runtime="$(get battery.runtime)"
        if [[ "$runtime" =~ ^[0-9]+$ ]]; then
          mins="$((runtime / 60)) min"
        else
          mins="unknown"
        fi

        notify-send -a "UPS" "UPS: ''${charge:-?}% (''${status})" "Load ''${load:-?}% -- runtime ''${mins}" || true
      '';
    };
  in {
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
        # A static UPS button in the bar's end lane (bottom of the left bar):
        # a battery glyph that opens live `upsc evo` on click. Noctalia v5's
        # custom_button cannot poll/display live text, so power-state
        # awareness comes from homeModules.upsIndicator's notifications; this
        # is the on-demand "show me the details" affordance. The list is the
        # built-in default end lane (config_types.h) with "ups" inserted.
        bar.main.end = [
          "media"
          "tray"
          "notifications"
          "clipboard"
          "network"
          "bluetooth"
          "volume"
          "brightness"
          "ups"
          "battery"
          "control-center"
          "session"
        ];
        widget.ups = {
          type = "custom_button";
          glyph = "battery";
          tooltip = "UPS -- click for charge & status";
          command = pkgs.lib.getExe ups-status-notify;
        };
        # Single source of "where am I"; feeds Weather, Night Light, and
        # Theme auto mode. Geocoded at runtime from the address.
        location = {
          auto_locate = false;
          address = "Lisbon, Portugal";
        };
        # Wallpaper is handled by awww (see homeModules.niri).
        wallpaper.enabled = false;
        # awww owns the live wallpaper and is invisible to noctalia, so the
        # lock screen has nothing to fall back to (empty = noctalia's own
        # wallpaper, which is disabled above). Point it at the same image awww
        # paints.
        lockscreen.wallpaper = "${./niri/gruvbox-mountain-village.png}";
        # Lock after 5 minutes of inactivity, then power the displays off
        # after 10. screen_off drives niri's PowerOffMonitors IPC; noctalia
        # wakes them on activity (PowerOnMonitors). Desktop, so no suspend.
        idle.behavior = {
          lock = {
            enabled = true;
            timeout = 300;
            action = "lock";
          };
          screen-off = {
            enabled = true;
            timeout = 600;
            action = "screen_off";
          };
        };
      };
    };
  };
}
