{inputs, ...}: {
  flake.nixosModules.nix = {
    pkgs,
    lib,
    ...
  }: {
    imports = [
      inputs.nix-index-database.nixosModules.nix-index
    ];
    programs.nix-index-database.comma.enable = true;

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
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
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
