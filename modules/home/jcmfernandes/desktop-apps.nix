{
  flake.homeModules.desktop-apps = {pkgs, ...}: {
    home.packages = [
      pkgs.nautilus
      pkgs.easyeffects
      pkgs.insync
      pkgs.vlc
      pkgs.unrar
      pkgs.file-roller
      pkgs.libreoffice
      pkgs.gimp
      pkgs.zathura
      pkgs.foliate
      pkgs.qbittorrent
      pkgs.gparted
      pkgs.wdisplays
      pkgs.celluloid
      pkgs.element-desktop
      pkgs.halloy
    ];
  };
}
