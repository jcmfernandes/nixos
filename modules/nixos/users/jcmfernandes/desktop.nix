{self, ...}: {
  # What only a graphical host adds on top of nixosModules.jcmfernandes:
  # the device/virtualisation groups and the GUI home modules. Both lists
  # merge with the base module's -- extraGroups concatenates, and each
  # definition of home-manager.users.jcmfernandes is another module whose
  # imports are all honoured.
  flake.nixosModules.jcmfernandesDesktop = {
    users.users.jcmfernandes.extraGroups = [
      "networkmanager"
      "input"
      "uinput"
      "video"
      "render"
      "libvirtd"
    ];

    home-manager.users.jcmfernandes.imports = [
      self.homeModules.yubikey-ssh
      self.homeModules.noctalia
      self.homeModules.which-key
      self.homeModules.kitty
      self.homeModules.niri
      self.homeModules.gtk
      self.homeModules.desktop-apps
      self.homeModules.insync
      self.homeModules.fonts
      self.homeModules.flatpak
      self.homeModules.firefox
      self.homeModules.emacs
      self.homeModules.enchant
      self.homeModules.easyeffects
      self.homeModules.upsIndicator
    ];
  };
}
