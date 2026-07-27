_: {
  # Small set of laptop hardware defaults karma (a desktop) does not need.
  # Lid-close suspend is systemd-logind's default and left unset; the
  # touchpad is handled by niri's libinput.
  flake.nixosModules.laptop = {pkgs, ...}: {
    # Power profile switching (balanced/performance/power-saver). upower is
    # already enabled by the desktop module.
    services.power-profiles-daemon.enable = true;

    # Firmware updates -- laptops get LVFS-delivered firmware often.
    services.fwupd.enable = true;

    # Backlight control from the CLI / niri binds. The noctalia brightness
    # widget already exists; the user is in the "video" group.
    environment.systemPackages = [pkgs.brightnessctl];
  };
}
