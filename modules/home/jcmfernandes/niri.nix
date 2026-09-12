{
  self,
  inputs,
  ...
}: {
  flake.homeModules.niri = {
    lib,
    pkgs,
    osConfig,
    ...
  }: let
    noctaliaExe = lib.getExe inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;

    settings = {
      prefer-no-csd = _: {};

      # Named explicitly because the default ("default", size 24) resolves to
      # nothing on this system and niri then draws its built-in pointer at a
      # fixed size, ignoring the output scale. The theme itself is installed by
      # homeModules.gtk's home.pointerCursor. niri also exports these as
      # XCURSOR_THEME/XCURSOR_SIZE to everything it spawns.
      cursor = {
        xcursor-theme = "Adwaita";
        xcursor-size = 24;
      };

      # Don't pop the "Important Hotkeys" cheat-sheet on every login;
      # summon it on demand with Mod+Shift+Slash instead.
      hotkey-overlay.skip-at-startup = _: {};

      input = {
        # focus-follows-mouse is deliberately NOT set: merely moving the
        # pointer over a window (a fullscreen one especially) should never
        # steal focus. Focus changes on click or via the Mod binds below.

        keyboard = {
          xkb = {
            layout = "us,pt";
            # Layout switching is a niri bind (Mod+Space, see binds), not an
            # xkb group toggle.
            #
            # Per host: karma keeps the default (Caps Lock as an extra Esc),
            # anuchka swaps Caps Lock with Left Ctrl.
            options = osConfig.preferences.xkbOptions;
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
          natural-scroll = _: {};
        };
      };

      binds = {
        "Mod+Return".spawn = "kitty";

        "Mod+Space".switch-layout = "next";

        "Mod+Q".close-window = _: {};
        "Mod+M".maximize-group = _: {};
        "Mod+F".fullscreen-window = _: {};
        "Mod+G".toggle-window-floating = _: {};
        "Mod+Shift+G".switch-focus-between-floating-and-tiling = _: {};
        "Mod+S".toggle-group-tabbed-display = _: {};
        "Mod+C".center-group = _: {};

        # Loose analog to Pop's "change orientation": pull the neighbouring
        # window into the focused group, or push one back out. Neither
        # action names a direction, so both work whatever the output's
        # orientation -- unlike consume-or-expel-window-left/right, which
        # are horizontal-only and dead on DP-2.
        "Mod+O".consume-window-into-group = _: {};
        "Mod+Shift+O".expel-window-from-group = _: {};

        # The fused window-or-group actions name a physical direction and
        # act on whatever lies that way: the window inside the group, or
        # the adjacent group. Windows and groups run along perpendicular
        # axes, so exactly one applies on any output -- which is what keeps
        # hjkl and the arrows spatially correct on both the horizontal
        # main screen and the vertical DP-2.
        "Mod+H".focus-window-or-group-left = _: {};
        "Mod+L".focus-window-or-group-right = _: {};
        "Mod+K".focus-window-or-group-up = _: {};
        "Mod+J".focus-window-or-group-down = _: {};

        "Mod+Left".focus-window-or-group-left = _: {};
        "Mod+Right".focus-window-or-group-right = _: {};
        "Mod+Up".focus-window-or-group-up = _: {};
        "Mod+Down".focus-window-or-group-down = _: {};

        # hjkl = niri structural editing: reorder within the strip/group.
        "Mod+Shift+H".move-window-or-group-left = _: {};
        "Mod+Shift+L".move-window-or-group-right = _: {};
        "Mod+Shift+K".move-window-or-group-up = _: {};
        "Mod+Shift+J".move-window-or-group-down = _: {};

        # Arrows = Pop spatial navigation. Ctrl navigates (workspaces
        # vertically, monitors horizontally); Shift moves the window
        # there; Ctrl+Shift moves it to a vertically-stacked monitor.
        "Mod+Ctrl+Up".focus-workspace-up = _: {};
        "Mod+Ctrl+Down".focus-workspace-down = _: {};
        "Mod+Ctrl+Left".focus-monitor-left = _: {};
        "Mod+Ctrl+Right".focus-monitor-right = _: {};

        # Workspaces run across the layout orientation, so the up/down
        # spellings above are horizontal-output-only. These are their
        # vertical twins, live on DP-2 and inert everywhere else.
        "Mod+Ctrl+Shift+Left".focus-workspace-left = _: {};
        "Mod+Ctrl+Shift+Right".focus-workspace-right = _: {};

        # Likewise horizontal-only. On DP-2 use Mod+Shift+1..0, which
        # names the workspace and so works on either orientation.
        "Mod+Shift+Up".move-group-to-workspace-up = _: {};
        "Mod+Shift+Down".move-group-to-workspace-down = _: {};
        "Mod+Shift+Left".move-group-to-monitor-left = _: {};
        "Mod+Shift+Right".move-group-to-monitor-right = _: {};

        "Mod+Ctrl+Shift+Up".move-group-to-monitor-up = _: {};
        "Mod+Ctrl+Shift+Down".move-group-to-monitor-down = _: {};

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

        "Mod+Shift+1".move-group-to-workspace = "w0";
        "Mod+Shift+2".move-group-to-workspace = "w1";
        "Mod+Shift+3".move-group-to-workspace = "w2";
        "Mod+Shift+4".move-group-to-workspace = "w3";
        "Mod+Shift+5".move-group-to-workspace = "w4";
        "Mod+Shift+6".move-group-to-workspace = "w5";
        "Mod+Shift+7".move-group-to-workspace = "w6";
        "Mod+Shift+8".move-group-to-workspace = "w7";
        "Mod+Shift+9".move-group-to-workspace = "w8";
        "Mod+Shift+0".move-group-to-workspace = "w9";

        "Mod+Slash".spawn-sh = "${noctaliaExe} msg panel-toggle launcher";
        "Mod+Shift+Slash".show-hotkey-overlay = _: {};
        "Mod+Escape".spawn-sh = "${noctaliaExe} msg session lock";
        "Mod+V".spawn-sh = ''${pkgs.alsa-utils}/bin/amixer sset Capture toggle'';

        "XF86AudioRaiseVolume".spawn-sh = "wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%+";
        "XF86AudioLowerVolume".spawn-sh = "wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%-";
        "XF86AudioMute".spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";

        # niri only acts on keys it binds; unbound media keys never reach
        # Spotify (a Wayland flatpak that doesn't grab raw keysyms globally).
        # Drive it over MPRIS with playerctl instead.
        "XF86AudioPlay".spawn-sh = "${lib.getExe pkgs.playerctl} play-pause";
        "XF86AudioPause".spawn-sh = "${lib.getExe pkgs.playerctl} play-pause";
        "XF86AudioNext".spawn-sh = "${lib.getExe pkgs.playerctl} next";
        "XF86AudioPrev".spawn-sh = "${lib.getExe pkgs.playerctl} previous";

        # Fine resize; Mod+R cycles the group through preset sizes.
        #
        # Sizing has no fused actions, so the group families need keys
        # per orientation: the width family only acts on horizontal
        # outputs and the height family only on vertical ones. The
        # window family is different: set-window-height's name is
        # logical, not spatial -- it always resizes the window's
        # cross-axis share of its group, so it is live on BOTH
        # orientations and its physical meaning flips. (set-window-width
        # is deliberately not bound: on tiled windows it duplicates
        # set-group-width on horizontal and set-group-height on
        # vertical.)
        #
        #                        horizontal          vertical (DP-2)
        #   Mod+Ctrl+H/L         group width         --
        #   Mod+Ctrl+J/K         window height       window width
        #   Mod+Ctrl+Shift+J/K   --                  group height
        #   Mod+R / Mod+Shift+R  preset group width  preset group height
        "Mod+Ctrl+H".set-group-width = "-5%";
        "Mod+Ctrl+L".set-group-width = "+5%";
        "Mod+Ctrl+J".set-window-height = "-5%";
        "Mod+Ctrl+K".set-window-height = "+5%";
        "Mod+R".switch-preset-group-width = _: {};

        "Mod+Ctrl+Shift+J".set-group-height = "-5%";
        "Mod+Ctrl+Shift+K".set-group-height = "+5%";
        "Mod+Shift+R".switch-preset-group-height = _: {};

        "Mod+WheelScrollDown".focus-window-or-group-left = _: {};
        "Mod+WheelScrollUp".focus-window-or-group-right = _: {};
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
      # than tiling it into a group. lxqt-openssh-askpass sets no app-id,
      # so match on its fixed window title.
      window-rules = [
        {
          matches = [{title = "^OpenSSH Authentication Passphrase request$";}];
          open-floating = true;
        }
      ];

      # Baremetal secondary screen, mounted rotated. No-op in the VM,
      # where DP-2 is not connected. 119.991 is the panel's ~120Hz mode at
      # native resolution (the round 120.000 modes only exist at lower res).
      outputs."DP-2" = {
        transform = "270";
        mode = "3840x2560@119.991";

        # Portrait, so the scrolling strip runs top-to-bottom here: new
        # windows stack downwards and the view scrolls vertically.
        # Directional actions are spatial, not logical: they follow the
        # physical direction they name, so an action is live on exactly
        # one orientation. The binds above use the fused
        # window-or-group actions where they exist, which is what keeps
        # hjkl and the arrows meaning the same thing on this output as on
        # the main screen; the rest carry vertical twins on separate keys.
        layout = {
          orientation = "vertical";
        };
      };

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

      # Nothing to spawn: noctalia (bar, wallpaper, lock screen) runs as its
      # own systemd user service -- see homeModules.noctalia.
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
