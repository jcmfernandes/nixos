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

    persistance.data.directories = [
      "nixconf"

      "Videos"
      "Documents"
      "Projects"

      ".ssh"
    ];

    # todo: remove
    persistance.cache.directories = [
      ".local/share/direnv"
    ];
  };
}