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

      # Display-bound CLI tools, kept out of homeModules.shell so headless
      # hosts don't carry them.
      # Run remote Wayland GUI apps over ssh.
      waypipe
      # Minimal Wayland image viewer.
      imv
      # Video player.
      mpv
      # wl-copy/wl-paste for the Wayland clipboard.
      wl-clipboard
    ];
  };
}
