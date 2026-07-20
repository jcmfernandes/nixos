{self, ...}: {
  flake.nixosModules.general = {
    pkgs,
    config,
    ...
  }: {
    imports = [
      #      self.nixosModules.gtk
      self.nixosModules.nix
    ];

    persistence.data.directories = [
      "nixconf"

      "Videos"
      "Documents"
      "Projects"

      ".ssh"
    ];

    # todo: remove
    persistence.cache.directories = [
      ".local/share/direnv"
    ];
  };
}
