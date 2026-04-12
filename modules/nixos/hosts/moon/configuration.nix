{ self, inputs, ... }: {

  flake.nixosModules.moonConfiguration = { config, ... }: {
    imports = with inputs.nixos-raspberrypi.nixosModules; [
      raspberry-pi-5.base
      raspberry-pi-5.page-size-16k
      raspberry-pi-5.display-vc4

      self.nixosModules.base
      self.nixosModules.general
    ];

    boot.loader.raspberry-pi.bootloader = "kernel";
    boot.extraModprobeConfig = "options cfg80211 ieee80211_regdom=PT";

    networking = {
      hostName = "moon";
      useDHCP = true;
      # DNS:
      # - https://dns.sb
      # - https://joindns4.eu/for-public
      nameservers = [ "185.222.222.222" "2a09::" "86.54.11.100" "2a13:1001::86:54:11:100" ];
      networkmanager.enable = true;
      networkmanager.ensureProfiles.profiles."VizinhosDo5E" = {
        connection = {
          id = "VizinhosDo5E";
          type = "wifi";
        };
        wifi = {
          ssid = "VizinhosDo5E";
          mode = "infrastructure";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "pasteisdenata";
        };
      };
    };

    time.timeZone = "UTC";

    users.users.nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" "video" ];
      initialHashedPassword = "";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKswlDw7JPtBM7bX9yk4Cs3xMJMl3gQh40cKfNuvG4NM jcmfernandes@slashid-laptop"
      ];
    };

    users.users.root = {
      initialHashedPassword = "";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKswlDw7JPtBM7bX9yk4Cs3xMJMl3gQh40cKfNuvG4NM jcmfernandes@slashid-laptop"
      ];
    };

    security.sudo.wheelNeedsPassword = false;

    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "yes";
    };

    services.plex = {
      enable = true;
      openFirewall = true;
    };

    system.stateVersion = config.system.nixos.release;
  };

}
