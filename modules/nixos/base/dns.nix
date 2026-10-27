{
  flake.nixosModules.base = {
    networking = {
      # DNS:
      # - https://joindns4.eu/for-public (unfiltered)
      # - https://blog.uncensoreddns.org/dns-servers/ (anycast)
      # IPv4 first: glibc reads only the first three.
      nameservers = [
        "86.54.11.100"
        "91.239.100.100"
        "2a13:1001::86:54:11:100"
        "2001:67c:28a4::"
      ];
      # Keep DHCP/RA-provided resolvers out of resolv.conf, so the above
      # are the only upstreams (tailscale's MagicDNS forwards to them too).
      dhcpcd.extraConfig = "nohook resolv.conf";
      networkmanager.dns = "none";
    };
  };
}
