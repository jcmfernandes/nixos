{pkgs, ...}: {
  packages = with pkgs; [
    yubikey-manager # ykman
    sops
    age-plugin-yubikey
    ssh-to-age
    openssh # ssh-keygen for host-key generation
    nixos-anywhere
    nixos-rebuild
    attic-client
    gitleaks
    nixd # Nix LSP
    alejandra
    statix
  ];

  git-hooks.hooks = {
    alejandra.enable = true;
    statix.enable = true;
    shellcheck = {
      enable = true;
      # The scripts carry a few deliberate info-level patterns (e.g.
      # client-side expansion in scp-flake.sh); only fail on warnings up.
      args = ["--severity=warning"];
      # .envrc files are direnv scripts: no shebang by design (SC2148).
      excludes = ["\\.envrc$"];
    };
    gitleaks = {
      enable = true;
      entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged --redact";
      pass_filenames = false;
    };
  };
}
