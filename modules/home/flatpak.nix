{inputs, ...}: {
  flake.homeModules.flatpak = {
    imports = [inputs.nix-flatpak.homeManagerModules.nix-flatpak];

    # Apps better delivered via Flathub than nixpkgs (fresher Slack/Zoom,
    # sandboxed). nix-flatpak installs/updates these on activation, so the
    # set stays declarative -- now user-scope instead of system-scope.
    # services.flatpak.enable (the system daemon) is set in the host config.
    services.flatpak = {
      remotes = [
        {
          name = "flathub";
          location = "https://flathub.org/repo/flathub.flatpakrepo";
        }
      ];
      packages = [
        "com.spotify.Client"
        "com.slack.Slack"
        "us.zoom.Zoom"
        "com.github.tchx84.Flatseal"
        "com.discordapp.Discord"
        "org.signal.Signal"
      ];
    };
  };
}
