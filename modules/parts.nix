{inputs, ...}: {
  options = {
    flake = inputs.flake-parts.lib.mkSubmoduleOptions {
      wrapperModules = inputs.nixpkgs.lib.mkOption {
        # Values are heterogeneous (plain module fragments, but also
        # wrapModule results consumed via .apply), so raw: passed through
        # untouched, and defining the same name twice is an eval error
        # instead of a silent overwrite.
        type = inputs.nixpkgs.lib.types.lazyAttrsOf inputs.nixpkgs.lib.types.raw;
        default = {};
      };
      homeModules = inputs.nixpkgs.lib.mkOption {
        # Home Manager module fragments, consumed via
        # home-manager.users.<name>.imports. deferredModule matches how
        # flake-parts types nixosModules (flake-parts does not declare
        # homeModules itself).
        type = inputs.nixpkgs.lib.types.lazyAttrsOf inputs.nixpkgs.lib.types.deferredModule;
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
    perSystem = {
      system,
      pkgs,
      ...
    }: {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # `nix fmt` formats the tree with the repo's formatter.
      formatter = pkgs.alejandra;
    };
  };
}
