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
    # them itself). The two switchable PowerShare outlets are toggled out of
    # band, e.g.:
    #   upscmd -u upsmon evo outlet.1.load.on   # or .off (also outlet.2)
    # That on/off state is persistent UPS hardware state, not managed here.
    environment.systemPackages = [config.power.ups.package];

    # Local-only NUT auth secret (upsmon <-> upsd on localhost). Restart the
    # daemons when it rotates. Declared here to keep the UPS concern
    # self-contained; uses karma's defaultSopsFile (secrets/karma.yaml).
    sops.secrets.ups_upsmon_password = {
      restartUnits = ["upsd.service" "upsmon.service"];
    };
  };
}
