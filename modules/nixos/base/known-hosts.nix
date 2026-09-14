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
      hosts
      // {
        # GitHub serves its host keys over HTTPS at
        # https://api.github.com/meta, so pinning them here replaces ssh's
        # trust-on-first-use prompt with trust anchored in the web PKI.
        # ed25519 only: ssh prefers a key type already present in
        # known_hosts, so the rsa and ecdsa keys GitHub also offers are
        # never negotiated and pinning them adds nothing.
        "github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      };
  };
}
