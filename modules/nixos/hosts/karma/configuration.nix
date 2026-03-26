{ self, inputs, ... }: {

  flake.nixosModules.karmaConfiguration = { pkgs, lib, ... }: let
    selfpkgs = self.packages."${pkgs.stdenv.hostPlatform.system}";
  in {
    imports = [
      self.nixosModules.karmaHardware

      self.nixosModules.base
      self.nixosModules.general
      self.nixosModules.desktop

      # disko
      inputs.disko.nixosModules.disko
      self.diskoConfigurations.karma
    ];

    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    boot = {
      kernelParams = [ "video=Virtual-1:1920x1080" ];
      kernelPackages = pkgs.linuxPackages_latest;
      loader.grub = {
        # no need to set devices, disko will add all devices that have a EF02 partition to the list already
        # devices = [ ];
        efiSupport = true;
        efiInstallAsRemovable = true;
      };
    };

    networking = {
      hostName = "karma";
      networkmanager.enable = true;
    };

    virtualisation.libvirtd.enable = true;
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings = {
        dns_enabled = true;
      };
    };

    services = {
      openssh.enable = true;
      flatpak.enable = true;
      udisks2.enable = true;
      printing.enable = true;
    };

    programs = {
      appimage.enable = true;
      zsh.enable = true;
    };

    environment.systemPackages = with pkgs; [
      git
      glib
    ];

    xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];
    xdg.portal.enable = true;

    environment.shells = [ (lib.getExe selfpkgs.environment) ];

    users.users.jcmfernandes = {
      isNormalUser = true;
      shell = lib.getExe selfpkgs.environment;
      extraGroups = [ "wheel" "networkmanager" "input" "uinput" "video" "render" ];
      hashedPassword = "$6$mTNpK1zBZ9ksDGWA$vtotYvcTAeu3J8ZJAB6LSlVxPu9L.FCNI16eTfrvVv7wjc7FuBqvccE4hYzW9hr/pf1oHyhQxs7UEV.wRww4L1";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbASIFlmPoZBGPJuhertdKSWBvCZyw60WrAhRu+/4nG nixos-anywhere"
      ];
    };
  
    users.users.root.hashedPassword = "!";
  
    system.stateVersion = "25.11";
  };

}