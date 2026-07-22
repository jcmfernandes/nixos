{
  flake.homeModules.firefox = {
    programs.firefox.enable = true;
    # The existing profile lives at ~/.mozilla/firefox; keep it there (the
    # upstream default moves under XDG_CONFIG_HOME at stateVersion 26.05,
    # which would require migrating the profile by hand).
    programs.firefox.configPath = ".mozilla/firefox";
  };
}
