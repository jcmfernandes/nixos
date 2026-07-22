{self, ...}: {
  flake.homeModules.kitty = {
    programs.kitty = {
      enable = true;

      font = {
        name = "JetBrainsMono Nerd Font";
        size = 15;
      };

      # Keep kitty.conf equivalent to the previously wrapped config: the raw
      # shell_integration value is carried in `settings`, so hm's own
      # integration plumbing (which force-prepends no-rc) is disabled.
      shellIntegration = {
        mode = null;
        enableBashIntegration = false;
        enableFishIntegration = false;
        enableZshIntegration = false;
      };

      settings = {
        enable_audio_bell = "no";

        cursor_text_color = "background";

        allow_remote_control = "yes";
        shell_integration = "enabled";

        cursor_trail = 3;

        background = self.theme.base00;
        foreground = self.theme.base07;

        cursor = self.theme.base07;

        selection_foreground = self.theme.base02;
        selection_background = self.theme.base01;

        active_tab_foreground = self.theme.base0B;
        active_tab_background = self.theme.base03;
        inactive_tab_background = self.theme.base01;

        color0 = self.theme.base00;
        color8 = self.theme.base02;
        color1 = self.theme.base08;
        color9 = self.theme.base08;
        color2 = self.theme.base0B;
        color10 = self.theme.base0B;
        color3 = self.theme.base0A;
        color11 = self.theme.base0A;
        color4 = self.theme.base0D;
        color12 = self.theme.base0D;
        color5 = self.theme.base0E;
        color13 = self.theme.base0E;
        color6 = self.theme.base0C;
        color14 = self.theme.base0C;
        color7 = self.theme.base03;
        color15 = self.theme.base03;
      };

      keybindings = {
        "alt+1" = "goto_tab 1";
        "alt+2" = "goto_tab 2";
        "alt+3" = "goto_tab 3";
        "alt+4" = "goto_tab 4";
        "alt+5" = "goto_tab 5";
        "alt+6" = "goto_tab 6";
        "alt+7" = "goto_tab 7";
        "alt+8" = "goto_tab 8";
        "alt+9" = "goto_tab 9";
        "ctrl+shift+w" = "close_tab";
        "ctrl+t" = "new_tab_with_cwd";
        "ctrl+shift+t" = "new_tab";
      };
    };
  };
}
