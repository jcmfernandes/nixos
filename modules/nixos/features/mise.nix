_: {
  flake.nixosModules.mise = {pkgs, ...}: {
    # mise: polyglot per-project tool/runtime version manager. The interactive
    # shell activates it via `mise activate zsh` (homeModules.shell).
    #
    # `usage` is a hard runtime dependency of mise's shell completions --
    # mise shells out to it to render them, and without it every completion
    # attempt errors with "usage CLI not found".
    environment.systemPackages = [pkgs.mise pkgs.usage];

    # Force mise to fetch precompiled binaries instead of building from source.
    # Source builds of node/python shell out to a bootstrap `python`, which
    # NixOS does not provide on PATH, so they fail. This keeps mise on the
    # FHS-linked prebuilt path that nix-ld below makes runnable.
    environment.sessionVariables = {
      MISE_NODE_COMPILE = "0";
      MISE_PYTHON_COMPILE = "0";
    };

    # mise installs mostly precompiled, FHS-linked binaries (node, go, the
    # standalone Python/Ruby builds, ...). nix-ld provides the dynamic loader
    # at the FHS path plus common libraries so those binaries run on NixOS.
    # Add to `libraries` if a specific tool reports a missing .so.
    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [
      zlib
      openssl
      stdenv.cc.cc.lib
    ];
  };
}
