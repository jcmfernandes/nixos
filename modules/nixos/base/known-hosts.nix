{
  flake.nixosModules.base = let
    hosts = {
      anuchka = "AAAAC3NzaC1lZDI1NTE5AAAAIHVj2qZN/GktjQhjP6T0uZVQ3sfp9Zds+1T2GGMNClhr";
      karma = "AAAAC3NzaC1lZDI1NTE5AAAAIH9A8z6cfz8aifq6fxe0mNr8tXVuuYB4XwHqSEkOCCoZ";
      moon = "AAAAC3NzaC1lZDI1NTE5AAAAIEZGTLWzZZAz5G/zniguV/Fy6K6RquSc2Dw8aPNLLISn";
      vivivi = "AAAAC3NzaC1lZDI1NTE5AAAAIOuy8a/EmZC+gegkKUOZBA3MQeAZwEzaUBjig/gVQhvC";
    };
  in {
    # Every host trusts every other host's ssh host key, so ssh between
    # them (interactive, remote builds, deploys) never prompts. Public
    # keys only; the private halves stay on each host (and in that
    # host's secrets/<host>.yaml). Rotate here when a host is reinstalled.
    programs.ssh.knownHosts =
      builtins.mapAttrs (name: key: {
        hostNames = [
          name
          "${name}.hosts.moreirafernandes.com"
          "${name}.tail184b8c.ts.net"
        ];
        publicKey = "ssh-ed25519 ${key}";
      })
      hosts;
  };
}
