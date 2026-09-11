{
  flake.nixosModules.base = {lib, ...}: {
    options.preferences = {
      xkbOptions = lib.mkOption {
        type = lib.types.str;
        default = "caps:escape";
        example = "ctrl:swapcaps";
        description = ''
          Comma-separated xkb options for the compositor's keyboard, read by
          homeModules.niri via osConfig. An option rather than a literal in
          the home module, because that module is shared by every desktop
          host and the hosts disagree: karma keeps Caps Lock as an extra Esc,
          anuchka swaps Caps Lock with Left Ctrl.
        '';
      };
    };
  };
}
