_: {
  flake.homeModules.upsIndicator = {
    lib,
    pkgs,
    osConfig,
    ...
  }: let
    # Poll the local NUT server and raise a desktop notification whenever the
    # UPS power state changes. Runs as a user service so notify-send reaches
    # the session's notification daemon (noctalia). upsmon still owns the
    # actual clean shutdown; this is purely for at-a-glance awareness, since
    # Noctalia v5 has no command-polling bar widget that could show it live.
    ups-notify = pkgs.writeShellApplication {
      name = "ups-notify";
      runtimeInputs = [pkgs.nut pkgs.libnotify];
      text = ''
        ups="evo"
        interval="''${UPS_NOTIFY_INTERVAL:-10}"

        # Collapse ups.status (e.g. "OL CHRG", "OB", "OB LB") to one of:
        # online | onbattery | low | comm-lost. LB wins over OB wins over OL.
        classify() {
          local s
          if ! s="$(upsc "$ups" ups.status 2>/dev/null)" || [ -z "$s" ]; then
            echo "comm-lost"
            return
          fi
          case " $s " in
            *" LB "*) echo "low" ;;
            *" OB "*) echo "onbattery" ;;
            *) echo "online" ;;
          esac
        }

        notify() {
          # $1 urgency, $2 summary, $3 body
          notify-send -a "UPS" -u "$1" "$2" "$3" || true
        }

        # Silent baseline so we do not notify the current state at startup.
        prev="$(classify)"
        while true; do
          sleep "$interval"
          cur="$(classify)"
          if [ "$cur" = "$prev" ]; then
            continue
          fi
          case "$cur" in
            onbattery)
              notify critical "UPS on battery" "Mains power lost -- running on battery."
              ;;
            low)
              notify critical "UPS battery low" "Battery low -- system will shut down soon."
              ;;
            online)
              # Suppress the boot-time comm-lost -> online transition.
              if [ "$prev" != "comm-lost" ]; then
                notify normal "Mains power restored" "UPS back on line power."
              fi
              ;;
            comm-lost)
              notify critical "UPS unreachable" "Lost contact with the UPS (upsd)."
              ;;
          esac
          prev="$cur"
        done
      '';
    };
  in
    # Only on hosts that actually have a UPS (the `ups` NixOS module, imported
    # by karma, sets power.ups.enable). anuchka and future UPS-less hosts get
    # nothing.
    lib.mkIf osConfig.power.ups.enable {
      systemd.user.services.ups-notify = {
        Unit = {
          Description = "Desktop notifications on UPS (NUT) power state changes";
          # Gate on a live session so the notification daemon is on the bus.
          After = ["niri.service"];
          Wants = ["niri.service"];
        };
        Service = {
          ExecStart = lib.getExe ups-notify;
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = ["graphical-session.target"];
      };
    };
}
