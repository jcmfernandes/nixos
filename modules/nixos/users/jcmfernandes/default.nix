{
  self,
  inputs,
  ...
}: {
  # The jcmfernandes user: system account plus its CLI home-manager payload
  # (homeModules.cli), for every host, headless or not. Graphical hosts also
  # import nixosModules.jcmfernandesDesktop (./desktop.nix). Hosts import
  # this next to the hm NixOS module; host-level hm policy
  # (useGlobalPkgs/useUserPackages) stays in the host configuration.
  flake.nixosModules.jcmfernandes = {
    lib,
    pkgs,
    ...
  }: {
    users.users.jcmfernandes = {
      isNormalUser = true;
      shell = pkgs.zsh;
      # Start this user's systemd manager at boot and keep it across
      # logouts, so user services (the emacs daemon) run without any
      # login, graphical or otherwise.
      linger = true;
      extraGroups = ["wheel"];
      hashedPassword = "$6$mTNpK1zBZ9ksDGWA$vtotYvcTAeu3J8ZJAB6LSlVxPu9L.FCNI16eTfrvVv7wjc7FuBqvccE4hYzW9hr/pf1oHyhQxs7UEV.wRww4L1";
      # Shared key list (includes the YubiKey PIV key), matching moon/vivivi.
      openssh.authorizedKeys.keys =
        lib.filter (s: s != "")
        (lib.splitString "\n" (lib.fileContents inputs.jcmfernandes-keys));
    };

    home-manager.users.jcmfernandes = {
      imports = [self.homeModules.cli];
      home.stateVersion = "25.11";
    };
  };
}
