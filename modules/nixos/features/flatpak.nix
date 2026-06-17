{ inputs, ... }: {
  flake.nixosModules.flatpak = {
    imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];

    # Apps better delivered via Flathub than nixpkgs (fresher Slack/Zoom,
    # sandboxed). nix-flatpak installs/updates these on nixos-rebuild, so the
    # set stays declarative. services.flatpak.enable is set in the host config.
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
      ];
    };
  };
}
