{
  self,
  inputs,
  ...
}: {
  flake.homeModules.which-key = {
    lib,
    pkgs,
    ...
  }: let
    noctaliaExe = lib.getExe inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
    yamlFormat = pkgs.formats.yaml {};
  in {
    # Read by wlr-which-key when invoked with no config argument (the Mod+d
    # bind in homeModules.niri).
    xdg.configFile."wlr-which-key/config.yaml".source = yamlFormat.generate "wlr-which-key-config.yaml" {
      menu = [
        {
          key = "b";
          desc = "Bluetooth";
          cmd = "${noctaliaExe} msg panel-toggle control-center bluetooth";
        }
        {
          key = "w";
          desc = "Wifi";
          cmd = "${noctaliaExe} msg panel-toggle control-center wifi";
        }
        {
          key = "f";
          desc = "Firefox";
          cmd = "firefox";
        }
        {
          key = "t";
          desc = "Telegram";
          cmd = "Telegram";
        }
        {
          key = "d";
          desc = "Discord";
          cmd = "vesktop";
        }
        {
          key = "m";
          desc = "Youtube Music";
          cmd = "pear-desktop";
        }
        {
          key = "s";
          desc = "Pavucontrol";
          cmd = "${lib.getExe pkgs.pavucontrol}";
        }
      ];

      font = "JetBrainsMono Nerd Font 12";
      background = self.theme.base00;
      color = self.theme.base06;
      border = self.theme.base0F;
      separator = " ➜ ";
      border_width = 2;
      corner_r = 15;
      padding = 15;
      rows_per_column = 5;
      column_padding = 25;

      anchor = "bottom-right";
      margin_right = 0;
      margin_bottom = 5;
      margin_left = 5;
      margin_top = 0;
    };
  };
}
