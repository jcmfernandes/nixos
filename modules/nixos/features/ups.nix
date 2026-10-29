_: {
  flake.nixosModules.ups = {config, ...}: {
    power.ups = {
      enable = true;
      mode = "standalone"; # driver + upsd + upsmon, all local

      ups.evo = {
        driver = "usbhid-ups";
        port = "auto";
        description = "MGE Pulsar Evolution 1100";
      };

      # NUT account upsmon uses to reach the local upsd (localhost only).
      users.upsmon = {
        passwordFile = config.sops.secrets.ups_upsmon_password.path;
        upsmon = "primary"; # grants the upsmon role in upsd.users
        # The upsmon role grants no instant commands; allow the outlet toggles.
        instcmds = [
          "outlet.1.load.on"
          "outlet.1.load.off"
          "outlet.2.load.on"
          "outlet.2.load.off"
        ];
      };

      upsmon.monitor.evo = {
        # Explicit upsname@hostname form (the option would default to the bare
        # name "evo") so upsmon's MONITOR line is well formed.
        system = "evo@localhost";
        user = "upsmon";
        type = "primary"; # this host is directly USB-attached
        # powerValue defaults to 1 (== MINSUPPLIES); passwordFile inherits
        # users.upsmon.passwordFile.
      };
    };

    # upsc/upscmd/upsrw on PATH for interactive use (power.ups does not add
    # them itself). The two switchable PowerShare outlets can be toggled by
    # hand, e.g.:
    #   upscmd -u upsmon evo outlet.1.load.on   # or .off (also outlet.2)
    environment.systemPackages = [config.power.ups.package];

    # The UPS forgets the outlet state once its battery is drained, so turn
    # both outlets on at every boot. Retries while upsd connects to the driver.
    systemd.services.ups-outlets-on = {
      description = "Turn on UPS PowerShare outlets";
      after = ["upsd.service" "upsdrv.service"];
      requires = ["upsd.service"];
      wantedBy = ["multi-user.target"];
      startLimitIntervalSec = 60;
      startLimitBurst = 5;
      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      path = [config.power.ups.package];
      script = ''
        p=$(< ${config.sops.secrets.ups_upsmon_password.path})
        upscmd -u upsmon -p "$p" evo outlet.1.load.on
        upscmd -u upsmon -p "$p" evo outlet.2.load.on
      '';
    };

    # Local-only NUT auth secret (upsmon <-> upsd on localhost). Restart the
    # daemons when it rotates. Declared here to keep the UPS concern
    # self-contained; uses karma's defaultSopsFile (secrets/karma.yaml).
    sops.secrets.ups_upsmon_password = {
      restartUnits = ["upsd.service" "upsmon.service"];
    };
  };
}
