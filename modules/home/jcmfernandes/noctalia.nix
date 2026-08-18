{inputs, ...}: {
  flake.homeModules.noctalia = {
    pkgs,
    lib,
    osConfig,
    ...
  }: let
    # UPS bar button + widget only on hosts with a UPS (the `ups` NixOS
    # module, imported by karma, sets power.ups.enable). anuchka and other
    # UPS-less hosts get a clean bar.
    upsEnabled = osConfig.power.ups.enable;

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
      #
      # Requisite, not Requires: Requires would let a restart of the bar pull
      # niri up, and niri started outside a logind session never becomes
      # active while still blocking every later login. Requisite keeps the
      # gate without the resurrection. (PartOf=graphical-session.target comes
      # from the upstream unit, so teardown is already covered.)
      After = ["niri.service"];
      Requisite = ["niri.service"];
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
      settings =
        {
          # Launch apps from the launcher into their own transient unit
          # (`systemd-run --user --property=ExitType=cgroup
          # --unit=app-<desktop-id>@<uuid>.service`) instead of letting them
          # fork inside noctalia.service's cgroup. Without this, home-manager
          # activation's `systemctl --user restart noctalia` on every switch
          # takes every launcher-started app down with the bar, because the
          # default KillMode=control-group SIGTERMs the whole cgroup -- which
          # is why firefox kept dying on rebuilds. Emacs already dodged this by
          # running as its own daemon (homeModules.emacs).
          shell.launch_apps_as_systemd_services = true;
          theme = {
            mode = "dark";
            source = "builtin";
            builtin = "Gruvbox";
          };
          bar.main.position = "left";
          # The built-in default end lane (config_types.h), plus "nightlight"
          # next to "brightness" (both are display controls; the button cycles
          # off / scheduled / always-on). On UPS hosts a static "ups" button (a
          # battery glyph that opens live `upsc evo` on click) is inserted
          # before "battery": Noctalia v5's custom_button cannot poll/display
          # live text, so power-state awareness comes from
          # homeModules.upsIndicator's notifications; this is the on-demand
          # "show me the details" affordance.
          bar.main.end =
            [
              "media"
              "tray"
              "notifications"
              "clipboard"
              "network"
              "bluetooth"
              "volume"
              "brightness"
              "nightlight"
            ]
            ++ lib.optional upsEnabled "ups"
            ++ [
              "battery"
              "control-center"
              "session"
            ];
          # Single source of "where am I"; feeds Weather, Night Light, and
          # Theme auto mode. Geocoded at runtime from the address.
          location = {
            auto_locate = false;
            address = "Lisbon, Portugal";
          };
          # Warm the screen after sunset -- what redshift did elsewhere.
          # Noctalia drives the wlr-gamma-control protocol itself (niri
          # implements it), so no wlsunset/gammastep helper is involved. The
          # schedule comes from `location` above; the 6500K/4000K day-night
          # defaults are left alone.
          nightlight.enabled = true;
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
        }
        // lib.optionalAttrs upsEnabled {
          widget.ups = {
            type = "custom_button";
            glyph = "battery";
            tooltip = "UPS -- click for charge & status";
            command = pkgs.lib.getExe ups-status-notify;
          };
        };
    };
  };
}
