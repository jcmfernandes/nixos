{ ... }: {
  flake.nixosModules.mise = { pkgs, ... }: {
    # mise: polyglot per-project tool/runtime version manager. The interactive
    # shell activates it via `mise activate zsh` (modules/wrappedPrograms).
    environment.systemPackages = [ pkgs.mise ];

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
