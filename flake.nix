{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "github:vic/import-tree";

    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wrapper-modules = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    emacs-pgtk-headless = {
      url = "github:jcmfernandes/emacs-pgtk-headless.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nixarr = {
      url = "github:nix-media-server/nixarr/282ce99b31d52d72cca281e3d26d3dd267946800";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Upstream rather than nixpkgs' devenv: the CLI nags on every shell load
    # when it is behind, and both our channels lag it (at the time of writing
    # 26.05 had 2.1.2 and unstable 2.2.2, against upstream's 2.3.2).
    #
    # Deliberately *not* `inputs.nixpkgs.follows`: keeping devenv's own pin is
    # what makes its prebuilt package match devenv.cachix.org, so no host has
    # to compile it -- which matters for aarch64 moon.
    devenv.url = "github:cachix/devenv";

    jcmfernandes-keys = {
      url = "https://github.com/jcmfernandes.keys";
      type = "file";
      flake = false;
    };

    niri = {
      url = "github:jcmfernandes/niri";
    };

    ohmyzsh = {
      url = "github:jcmfernandes/ohmyzsh";
      flake = false;
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
      "https://nix-community.cachix.org"
      "https://claude-code.cachix.org"
      "https://devenv.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    ];
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        (inputs.import-tree ./modules)
        # Declares `flake.diskoConfigurations` so multiple hosts can each
        # contribute their own entry without flake-parts complaining about
        # an undeclared option being defined multiple times.
        inputs.disko.flakeModule
      ];
    };
}
