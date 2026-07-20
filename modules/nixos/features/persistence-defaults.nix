{
  flake.nixosModules.persistenceDefaults = {
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
