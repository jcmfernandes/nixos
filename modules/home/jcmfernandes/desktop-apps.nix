{
  flake.homeModules.desktop-apps = {pkgs, ...}: {
    home.packages = [
      pkgs.nautilus
      pkgs.vlc
      pkgs.unrar
      pkgs.file-roller
      pkgs.libreoffice
      pkgs.gimp
      pkgs.loupe
      pkgs.zathura
      pkgs.foliate
      pkgs.qbittorrent
      pkgs.gparted
      pkgs.wdisplays
      pkgs.celluloid
      pkgs.pavucontrol
      pkgs.element-desktop
      pkgs.halloy
      pkgs.gnome-calculator
    ];
  };
}
