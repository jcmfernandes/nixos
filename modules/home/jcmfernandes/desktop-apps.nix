{
  flake.homeModules.desktop-apps = {pkgs, ...}: {
    home.packages = with pkgs; [
      calibre
      celluloid
      element-desktop
      file-roller
      foliate
      gimp
      gnome-calculator
      gparted
      halloy
      libreoffice
      loupe
      nautilus
      pavucontrol
      qbittorrent
      unrar
      vlc
      wdisplays
      zathura
    ];
  };
}
