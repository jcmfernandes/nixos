{
  inputs,
  self,
  ...
}: {
  flake.nixosModules.nix = {
    config,
    pkgs,
    lib,
    ...
  }: {
    imports = [
      inputs.nix-index-database.nixosModules.nix-index
    ];
    programs.nix-index-database.comma.enable = true;

    # Replace nixpkgs' devenv with upstream's (rationale in flake.nix). An
    # overlay rather than a one-off reference, so both consumers pick it up:
    # the direnvrc just below, and `home.packages` in the shell home module.
    #
    # x86_64 only. devenv's flake import-from-derivation-builds a patched
    # nixpkgs, so pulling it in for aarch64 makes `nix flake check` and
    # `nixos-rebuild build .#moon` fail on an x86_64 admin machine with
    # "platform mismatch" -- and moon/vivivi are servers nobody opens a devenv
    # shell on anyway. They keep nixpkgs' devenv.
    nixpkgs.overlays = [
      (final: prev:
        lib.optionalAttrs prev.stdenv.hostPlatform.isx86_64 {
          devenv = inputs.devenv.packages.${prev.stdenv.hostPlatform.system}.devenv;
        })
    ];

    programs.direnv = {
      enable = true;
      silent = false;
      loadInNixShell = true;
      # Define `use devenv` (the `use_devenv` direnv function this repo's
      # .envrc relies on). devenv prints its own direnvrc; without this the
      # .envrc fails with "use_devenv: command not found".
      direnvrcExtra = ''
        eval "$(${lib.getExe pkgs.devenv} direnvrc)"
      '';
      nix-direnv = {
        enable = true;
      };
      # Drop the "export +FOO +BAR ..." line direnv prints on every load. A
      # repo like ng-evangelion exports ~150 variables, which buries the rest
      # of the terminal; the "loading <path>/.envrc" line still shows, so it
      # stays obvious when an environment is applied.
      settings.global.hide_env_diff = true;
    };

    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["root" "@wheel"];
      download-buffer-size = 512 * 1024 * 1024;
      extra-substituters = [
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ];
    };

    # Authenticate nix against the GitHub API. Resolving a `github:` input to
    # a revision costs one api.github.com call, capped at 60/hour per IP when
    # unauthenticated; with ~30 such inputs a `nix flake update` exhausts it
    # partway through and then silently keeps the *cached* revision for
    # everything it could not reach. A token raises the cap to 5000/hour.
    #
    # Fleet-wide because every host evaluates flakes at some point: karma and
    # anuchka locally, moon and vivivi when deployed via scripts/scp-flake.sh
    # + a rebuild run on the host itself.
    #
    # !include rather than nix.settings.access-tokens: the latter would write
    # the token into the world-readable nix store.
    nix.extraOptions = ''
      !include ${config.sops.secrets.nix_access_tokens.path}
    '';

    # Owned by the user, not root: flake inputs are resolved by the nix CLI
    # running as whoever typed the command. Root-run rebuilds still read it
    # (root ignores the mode), so this covers both deploy styles.
    sops.secrets.nix_access_tokens = {
      sopsFile = "${self}/secrets/common.yaml";
      owner = "jcmfernandes";
    };

    programs.nix-ld.enable = true;
    nixpkgs.config.allowUnfree = true;

    environment.systemPackages = lib.optionals pkgs.stdenv.hostPlatform.isx86_64 (with pkgs; [
      # Nix tooling
      nil
      nixd
      statix
      alejandra
      manix
      nix-inspect
    ]);
  };
}
