{
  self,
  inputs,
  ...
}: {
  flake.homeModules.niri = {
    lib,
    pkgs,
    ...
  }: let
    noctaliaExe = lib.getExe inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;

    settings = {
      prefer-no-csd = _: {};

      # Don't pop the "Important Hotkeys" cheat-sheet on every login;
      # summon it on demand with Mod+Shift+Slash instead.
      hotkey-overlay.skip-at-startup = _: {};

      input = {
        focus-follows-mouse = _: {};

        keyboard = {
          xkb = {
            layout = "us,pt";
            # Layout switching is a niri bind (Mod+Space, see binds), not an
            # xkb group toggle.
            options = "caps:escape";
          };
          repeat-rate = 40;
          repeat-delay = 250;
        };

        touchpad = {
          natural-scroll = _: {};
          tap = _: {};
        };

        mouse = {
          accel-profile = "flat";
        };
      };

      binds = {
        "Mod+Return".spawn = "kitty";

        "Mod+Space".switch-layout = "next";

        "Mod+Q".close-window = _: {};
        "Mod+M".maximize-column = _: {};
        "Mod+F".fullscreen-window = _: {};
        "Mod+G".toggle-window-floating = _: {};
        "Mod+Shift+G".switch-focus-between-floating-and-tiling = _: {};
        "Mod+S".toggle-column-tabbed-display = _: {};
        "Mod+C".center-column = _: {};

        # Loose analog to Pop's "change orientation": pull a window into
        # the current column (vertical stack) or expel it back out.
        "Mod+O".consume-or-expel-window-right = _: {};
        "Mod+Shift+O".consume-or-expel-window-left = _: {};

        "Mod+H".focus-column-left = _: {};
        "Mod+L".focus-column-right = _: {};
        "Mod+K".focus-window-up = _: {};
        "Mod+J".focus-window-down = _: {};

        "Mod+Left".focus-column-left = _: {};
        "Mod+Right".focus-column-right = _: {};
        "Mod+Up".focus-window-up = _: {};
        "Mod+Down".focus-window-down = _: {};

        # hjkl = niri structural editing: reorder within the strip/column.
        "Mod+Shift+H".move-column-left = _: {};
        "Mod+Shift+L".move-column-right = _: {};
        "Mod+Shift+K".move-window-up = _: {};
        "Mod+Shift+J".move-window-down = _: {};

        # Arrows = Pop spatial navigation. Ctrl navigates (workspaces
        # vertically, monitors horizontally); Shift moves the window
        # there; Ctrl+Shift moves it to a vertically-stacked monitor.
        "Mod+Ctrl+Up".focus-workspace-up = _: {};
        "Mod+Ctrl+Down".focus-workspace-down = _: {};
        "Mod+Ctrl+Left".focus-monitor-left = _: {};
        "Mod+Ctrl+Right".focus-monitor-right = _: {};

        "Mod+Shift+Up".move-column-to-workspace-up = _: {};
        "Mod+Shift+Down".move-column-to-workspace-down = _: {};
        "Mod+Shift+Left".move-column-to-monitor-left = _: {};
        "Mod+Shift+Right".move-column-to-monitor-right = _: {};

        "Mod+Ctrl+Shift+Up".move-column-to-monitor-up = _: {};
        "Mod+Ctrl+Shift+Down".move-column-to-monitor-down = _: {};

        "Mod+Tab".toggle-overview = _: {};

        "Mod+1".focus-workspace = "w0";
        "Mod+2".focus-workspace = "w1";
        "Mod+3".focus-workspace = "w2";
        "Mod+4".focus-workspace = "w3";
        "Mod+5".focus-workspace = "w4";
        "Mod+6".focus-workspace = "w5";
        "Mod+7".focus-workspace = "w6";
        "Mod+8".focus-workspace = "w7";
        "Mod+9".focus-workspace = "w8";
        "Mod+0".focus-workspace = "w9";

        "Mod+Shift+1".move-column-to-workspace = "w0";
        "Mod+Shift+2".move-column-to-workspace = "w1";
        "Mod+Shift+3".move-column-to-workspace = "w2";
        "Mod+Shift+4".move-column-to-workspace = "w3";
        "Mod+Shift+5".move-column-to-workspace = "w4";
        "Mod+Shift+6".move-column-to-workspace = "w5";
        "Mod+Shift+7".move-column-to-workspace = "w6";
        "Mod+Shift+8".move-column-to-workspace = "w7";
        "Mod+Shift+9".move-column-to-workspace = "w8";
        "Mod+Shift+0".move-column-to-workspace = "w9";

        "Mod+Slash".spawn-sh = "${noctaliaExe} msg panel-toggle launcher";
        "Mod+Shift+Slash".show-hotkey-overlay = _: {};
        "Mod+Escape".spawn-sh = "${noctaliaExe} msg session lock";
        "Mod+V".spawn-sh = ''${pkgs.alsa-utils}/bin/amixer sset Capture toggle'';

        "XF86AudioRaiseVolume".spawn-sh = "wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%+";
        "XF86AudioLowerVolume".spawn-sh = "wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%-";

        # Fine resize; Mod+R cycles the column through preset widths.
        "Mod+Ctrl+H".set-column-width = "-5%";
        "Mod+Ctrl+L".set-column-width = "+5%";
        "Mod+Ctrl+J".set-window-height = "-5%";
        "Mod+Ctrl+K".set-window-height = "+5%";
        "Mod+R".switch-preset-column-width = _: {};

        "Mod+WheelScrollDown".focus-column-left = _: {};
        "Mod+WheelScrollUp".focus-column-right = _: {};
        "Mod+Ctrl+WheelScrollDown".focus-workspace-down = _: {};
        "Mod+Ctrl+WheelScrollUp".focus-workspace-up = _: {};

        "Mod+Ctrl+S".spawn-sh = ''${lib.getExe pkgs.grim} -l 0 - | ${pkgs.wl-clipboard}/bin/wl-copy'';

        "Mod+Shift+E".spawn-sh = ''${pkgs.wl-clipboard}/bin/wl-paste | ${lib.getExe pkgs.swappy} -f -'';

        "Mod+Shift+S".spawn-sh = lib.getExe (pkgs.writeShellApplication {
          name = "screenshot";
          text = ''
            ${lib.getExe pkgs.grim} -g "$(${lib.getExe pkgs.slurp} -w 0)" - \
            | ${pkgs.wl-clipboard}/bin/wl-copy
          '';
        });

        # Menu content and styling live in ~/.config/wlr-which-key/config.yaml
        # (homeModules.which-key), read by wlr-which-key when no config
        # argument is given.
        "Mod+d".spawn-sh = lib.getExe pkgs.wlr-which-key;
      };

      layout = {
        gaps = 5;

        focus-ring = {
          width = 2;
          active-color = "#${self.themeNoHash.base09}";
        };
      };

      # Float the OpenSSH askpass dialog (the YubiKey PIN prompt) rather
      # than tiling it into a column. lxqt-openssh-askpass sets no app-id,
      # so match on its fixed window title.
      window-rules = [
        {
          matches = [{title = "^OpenSSH Authentication Passphrase request$";}];
          open-floating = true;
        }
      ];

      # Baremetal secondary screen, mounted rotated. No-op in the VM,
      # where DP-2 is not connected.
      outputs."DP-2".transform = "270";

      workspaces = let
        workspaceSettings = {layout.gaps = 5;};
      in {
        "w0" = workspaceSettings;
        "w1" = workspaceSettings;
        "w2" = workspaceSettings;
        "w3" = workspaceSettings;
        "w4" = workspaceSettings;
        "w5" = workspaceSettings;
        "w6" = workspaceSettings;
        "w7" = workspaceSettings;
        "w8" = workspaceSettings;
        "w9" = workspaceSettings;
      };

      xwayland-satellite.path =
        lib.getExe pkgs.xwayland-satellite;

      # noctalia itself is started by its systemd user service (see
      # homeModules.noctalia), not spawned here.
      spawn-at-startup = [
        (lib.getExe (
          pkgs.writeShellScriptBin "wallpaper" ''
            ${pkgs.awww}/bin/awww-daemon &
            until ${lib.getExe pkgs.awww} query >/dev/null 2>&1; do sleep 0.1; done
            ${lib.getExe pkgs.awww} img ${./niri/gruvbox-mountain-village.png}
          ''
        ))
      ];
    };

    # Reuse the wrapper-modules niri module purely as a renderer: it turns
    # `settings` (the same DSL the wrapper used) into config.kdl text. The
    # wrapped package itself is never built or installed --
    # constructFiles.generatedConfig.path is a derivation placeholder, so
    # only .content is usable here.
    rendered =
      (inputs.wrapper-modules.lib.evalModule [
        {inherit pkgs;}
        inputs.wrapper-modules.wrapperModules.niri
        {inherit settings;}
      ]).config.constructFiles.generatedConfig.content;

    unvalidated = pkgs.writeText "niri-config-unvalidated.kdl" rendered;

    # Same build-time validation the wrapper's installPhase performed.
    configKdl = pkgs.runCommand "niri-config.kdl" {} ''
      ${lib.getExe pkgs.niri} validate -c ${unvalidated}
      cp ${unvalidated} $out
    '';
  in {
    # Plain niri (no NIRI_CONFIG baked in) reads this path and hot-reloads it
    # on change.
    xdg.configFile."niri/config.kdl".source = configKdl;
  };
}
