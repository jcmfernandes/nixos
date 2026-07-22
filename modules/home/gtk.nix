{
  flake.homeModules.gtk = {pkgs, ...}: let
    theme-name = "Gruvbox-Green-Dark-Medium";
    theme-package = pkgs.gruvbox-gtk-theme.override {
      colorVariants = ["dark"];
      sizeVariants = ["standard"];
      themeVariants = ["green"];
      tweakVariants = ["medium" "macos"];
    };

    icon-theme-package = pkgs.gruvbox-plus-icons;
    icon-theme-name = "Gruvbox-Plus-Dark";
  in {
    # Replaces the old system-wide mechanisms (/etc/xdg settings.ini, global
    # GTK_THEME, system dconf profile): hm writes the per-user gtk-3.0/gtk-4.0
    # settings and the org/gnome/desktop/interface dconf keys.
    gtk = {
      enable = true;
      theme = {
        name = theme-name;
        package = theme-package;
      };
      iconTheme = {
        name = icon-theme-name;
        package = icon-theme-package;
      };
      colorScheme = "dark";
    };

    # Carried over for parity with the old environment.variables.GTK_THEME;
    # lands in ~/.config/environment.d/ so the whole graphical session
    # (niri runs as a user service) sees it.
    systemd.user.sessionVariables.GTK_THEME = theme-name;

    # Parity with the old module, which installed these system-wide.
    home.packages = [pkgs.gtk3 pkgs.gtk4];
  };
}
