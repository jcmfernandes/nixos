{
  flake.homeModules.fonts = {pkgs, ...}: {
    fonts.fontconfig = {
      enable = true;
      defaultFonts = {
        serif = ["Ubuntu Sans"];
        sansSerif = ["Ubuntu Sans"];
        monospace = ["JetBrainsMono Nerd Font"];
      };
    };

    home.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      ubuntu-sans
      cm_unicode
      corefonts
      unifont
    ];
  };
}
