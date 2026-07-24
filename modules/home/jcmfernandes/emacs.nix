{
  flake.homeModules.emacs = {
    pkgs,
    lib,
    ...
  }: let
    # Plain Wayland-native emacs (emacs-pgtk), wrapped so straight.el's
    # runtime C compilation works on NixOS. Two packages in the config compile
    # native code on first use -- jinx (jinx-mod.c -> libenchant-2, found via
    # pkg-config) and tree-sitter grammars (treesit-install-language-grammar,
    # via cc/c++). NixOS has no /usr, so an unwrapped emacs can't find a
    # toolchain or enchant's pkg-config data. We give emacs' subprocesses just
    # those: a compiler (+pkg-config, git) on PATH and the .dev outputs of
    # enchant/glib on PKG_CONFIG_PATH. The nixpkgs cc-wrapper auto-embeds an
    # rpath into what it links, so the compiled modules find their libraries at
    # load time without any LD_LIBRARY_PATH (which would leak into every child
    # process emacs spawns).
    #
    # We deliberately do NOT use programs.emacs: it rebuilds its package through
    # emacsPackagesFor, which rejects a symlinkJoin-wrapped package. It only gave
    # us the binary + a .desktop anyway (config is stowed, no daemon), so we
    # deliver those directly via home.packages + xdg.desktopEntries below.
    emacs = pkgs.symlinkJoin {
      name = "emacs-native-build";
      paths = [pkgs.emacs-pgtk];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/emacs \
          --prefix PATH : ${lib.makeBinPath (with pkgs; [gcc binutils gnumake pkg-config git])} \
          --suffix PKG_CONFIG_PATH : ${lib.makeSearchPathOutput "dev" "lib/pkgconfig" (with pkgs; [enchant glib])}
      '';
    };

    # Launcher wired into the desktop entry below: ensure the daemon is up (a
    # no-op if graphical-session.target already started it), then attach a
    # frame. It deliberately never uses `emacsclient -a ""` -- that is the only
    # form that spawns a fresh daemon, and it would land in the launcher's
    # cgroup (e.g. noctalia's), recreating the very bug this daemon fixes.
    emacs-launch = pkgs.writeShellScriptBin "emacs-launch" ''
      ${pkgs.systemd}/bin/systemctl --user start emacs.service
      exec ${emacs}/bin/emacsclient -c "$@"
    '';
  in {
    home.packages = [emacs];

    # Emacs as a pgtk daemon owned by systemd, decoupled from whatever launched
    # a frame. Running the *wrapped* emacs so the daemon inherits the compiler
    # and PKG_CONFIG_PATH that straight.el needs for runtime native builds
    # (jinx, tree-sitter). We hand-roll the unit rather than use services.emacs
    # for the same reason emacs.nix avoids programs.emacs: it rebuilds the
    # package via emacsPackagesFor, which rejects the symlinkJoin wrapper.
    systemd.user.services.emacs = {
      Unit = {
        Description = "Emacs daemon (pgtk), wrapped for straight.el native builds";
        # Gate on a live Wayland socket so pgtk frames can be drawn. niri is a
        # Type=notify user service that signals readiness once its socket is
        # bound (same pattern as homeModules.noctalia's ordering).
        After = ["niri.service"];
        Requires = ["niri.service"];
        # Do NOT let home-manager activation stop or restart the daemon on a
        # nixos-rebuild switch: it -- and everything running inside it, incl.
        # the claude-code-ide session -- must survive every rebuild. A changed
        # emacs is adopted only on a manual `systemctl --user restart emacs` or
        # a reboot. keep-old is honoured by home-manager's sd-switch.
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "simple";
        ExecStart = "${emacs}/bin/emacs --fg-daemon";
        Restart = "on-failure";
      };
      Install.WantedBy = ["graphical-session.target"];
    };

    # Replaces the .desktop that programs.emacs generated, pointing the GUI
    # app-launcher entry at the daemon (via emacs-launch) instead of spawning a
    # fresh emacs. The launched emacsclient frame lives in the launcher's cgroup
    # and may close on a switch, but the daemon (and all buffers/subprocesses)
    # survives; reopening the entry reattaches losslessly.
    xdg.desktopEntries.emacs = {
      name = "Emacs";
      genericName = "Text Editor";
      exec = "${lib.getExe emacs-launch} %F";
      icon = "emacs";
      categories = ["Development" "TextEditor"];
      terminal = false;
    };
  };
}
