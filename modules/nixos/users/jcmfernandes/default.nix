{
  self,
  inputs,
  ...
}: {
  # The jcmfernandes user: system account plus its home-manager payload
  # (modules/home/jcmfernandes/). Hosts import this next to the hm NixOS
  # module; host-level hm policy (useGlobalPkgs/useUserPackages) stays in
  # the host configuration.
  flake.nixosModules.jcmfernandes = {
    lib,
    pkgs,
    ...
  }: {
    users.users.jcmfernandes = {
      isNormalUser = true;
      shell = pkgs.zsh;
      extraGroups = ["wheel" "networkmanager" "input" "uinput" "video" "render" "libvirtd"];
      hashedPassword = "$6$mTNpK1zBZ9ksDGWA$vtotYvcTAeu3J8ZJAB6LSlVxPu9L.FCNI16eTfrvVv7wjc7FuBqvccE4hYzW9hr/pf1oHyhQxs7UEV.wRww4L1";
      # Shared key list (includes the YubiKey PIV key), matching moon/vivivi.
      openssh.authorizedKeys.keys =
        lib.filter (s: s != "")
        (lib.splitString "\n" (lib.fileContents inputs.jcmfernandes-keys));
    };

    home-manager.users.jcmfernandes = {
      imports = [
        self.homeModules.yubikey-ssh
        self.homeModules.git
        self.homeModules.noctalia
        self.homeModules.shell
        self.homeModules.which-key
        self.homeModules.kitty
        self.homeModules.niri
        self.homeModules.gtk
        self.homeModules.desktop-apps
        self.homeModules.fonts
        self.homeModules.flatpak
        self.homeModules.firefox
        self.homeModules.emacs
        self.homeModules.tmux
        self.homeModules.zellij
        self.homeModules.enchant
      ];
      home.stateVersion = "25.11";
    };
  };
}
