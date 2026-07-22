{inputs, ...}: {
  options = {
    flake = inputs.flake-parts.lib.mkSubmoduleOptions {
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

    perSystem = {pkgs, ...}: {
      # `nix fmt` formats the tree with the repo's formatter.
      formatter = pkgs.alejandra;
    };
  };
}
