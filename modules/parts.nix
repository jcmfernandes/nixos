{ inputs, ... }: {
  imports = [
    # currently unused
    inputs.flake-parts.flakeModules.modules
  ];

  options = {
    flake = inputs.flake-parts.lib.mkSubmoduleOptions {
      wrapperModules = inputs.nixpkgs.lib.mkOption {
        default = {};
      };
    };
  };

  config = {
    systems = [
      "x86_64-linux"
    ];

    # Match the hosts' nixpkgs.config (features/nix.nix) so perSystem packages
    # (the wrapped desktop) can pull unfree deps too - e.g. niri transitively
    # needs `replace`, which nixpkgs 26.05 marks unfree.
    perSystem = { system, ... }: {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    };
  };
}