_: {
  # Small set of laptop hardware defaults karma (a desktop) does not need.
  # Lid-close suspend is systemd-logind's default and left unset; the
  # touchpad is handled by niri's libinput.
  flake.nixosModules.laptop = {
    config,
    pkgs,
    ...
  }: let
    # base/dns.nix ignores DHCP-provided resolvers. Captive portals that
    # block outside DNS until login need them back: `sudo captive on`, log
    # in, `sudo captive off`. resolvconf -x makes the router's resolvers
    # the only ones; tailscale's MagicDNS is paused meanwhile, else it
    # would keep forwarding to the static ones.
    captive = pkgs.writeShellApplication {
      name = "captive";
      runtimeInputs = [
        config.networking.networkmanager.package
        config.networking.resolvconf.package
        config.services.tailscale.package
      ];
      text = ''
        case "''${1:-}" in
          on)
            servers=$(nmcli -g IP4.DNS device show | tr '|' '\n' | tr -d ' ' | grep . | sed 's/^/nameserver /' || true)
            if [ -z "$servers" ]; then
              echo "captive: no DHCP-provided DNS servers found" >&2
              exit 1
            fi
            tailscale set --accept-dns=false
            resolvconf -x -a captive <<<"$servers"
            ;;
          off)
            resolvconf -d captive
            tailscale set --accept-dns=true
            ;;
          *)
            echo "usage: captive on|off" >&2
            exit 2
            ;;
        esac
      '';
    };
  in {
    # Power profile switching (balanced/performance/power-saver). upower is
    # already enabled by the desktop module.
    services.power-profiles-daemon.enable = true;

    # Firmware updates -- laptops get LVFS-delivered firmware often.
    services.fwupd.enable = true;

    # Backlight control from the CLI / niri binds. The noctalia brightness
    # widget already exists; the user is in the "video" group.
    environment.systemPackages = [pkgs.brightnessctl captive];
  };
}
