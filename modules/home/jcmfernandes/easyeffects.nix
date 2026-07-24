{
  flake.homeModules.easyeffects = {lib, ...}: let
    # The convolver kernels the presets reference by "kernel-name". Presets
    # only store the name; the .irs binary must sit in the irs data dir or
    # the convolver silently loads nothing. Linked per-file (not as a
    # directory) so ~/.local/share/easyeffects/irs stays writable for
    # IRs imported through the app.
    irsNames = [
      "Bowers & Wilkins PX7 S3 (ANC on, position 1) minimum phase 48000Hz.irs"
      "results_oratory1990_harman_over-ear_2018_Sony WH-1000XM3_Sony WH-1000XM3 minimum phase 48000Hz.irs"
    ];
  in {
    # HM-managed systemd user service; auto-loads BW at startup. Device
    # selection, window geometry, and the db/*rc runtime state stay mutable
    # and unmanaged -- only the output effect chains are declarative here.
    # (programs.dconf.enable, which the daemon needs, is set system-wide in
    # features/desktop.nix.)
    services.easyeffects = {
      enable = true;
      preset = "BW";
      extraPresets = {
        BW = builtins.fromJSON (builtins.readFile ./easyeffects/BW.json);
        XM3 = builtins.fromJSON (builtins.readFile ./easyeffects/XM3.json);
      };
    };

    # Filenames contain spaces/&/parens, so source is the store dir path
    # coerced to a string plus the name (a bare Nix path literal cannot hold
    # spaces).
    xdg.dataFile = lib.listToAttrs (map (n:
      lib.nameValuePair "easyeffects/irs/${n}" {
        source = "${./easyeffects/irs}/${n}";
      })
    irsNames);
  };
}
