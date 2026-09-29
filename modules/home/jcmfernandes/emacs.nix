{self, ...}: {
  flake.homeModules.emacs = {
    config,
    osConfig,
    pkgs,
    lib,
    ...
  }: let
    # Wayland-native emacs (emacs-pgtk-headless: emacs-pgtk plus the
    # compositor-survival patches, see emacs-pgtk-headless.nix), wrapped so
    # straight.el's
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
      paths = [config.jmf.emacs.package];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/emacs \
          --prefix PATH : ${lib.makeBinPath (with pkgs; [gcc binutils gnumake pkg-config git])} \
          --suffix PKG_CONFIG_PATH : ${lib.makeSearchPathOutput "dev" "lib/pkgconfig" (with pkgs; [enchant glib])}
      '';
    };

    # Launcher wired into the desktop entry below: ensure the daemon is up (a
    # no-op since it starts at boot with the user manager), then attach a
    # frame. It deliberately never uses `emacsclient -a ""` -- that is the only
    # form that spawns a fresh daemon, and it would land in the launcher's
    # cgroup (e.g. noctalia's), recreating the very bug this daemon fixes.
    emacs-launch = pkgs.writeShellScriptBin "emacs-launch" ''
      ${pkgs.systemd}/bin/systemctl --user start emacs.service
      exec ${emacs}/bin/emacsclient -c "$@"
    '';

    # Open a frame of <host>'s emacs daemon here, over waypipe. Closing the
    # frame ends emacsclient but not waypipe: emacs keeps a display's
    # connection open after its last frame goes (frame.c pins the terminal
    # to dodge a GTK bug), so waypipe would wait forever. Instead the remote
    # side kills waypipe's server process group -- the server and its
    # per-connection children -- and the daemon, being emacs-pgtk-headless,
    # survives the hangup. Killed, waypipe can't unlink its sockets, so we
    # do. Only hosts that run the daemon (import homeModules.emacs) qualify.
    emacs-remote = pkgs.writeShellScriptBin "emacs-remote" ''
      remote='emacsclient -c; rm -f "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "/tmp/waypipe-server-''${WAYLAND_DISPLAY#wayland-}.sock"; kill -- -$PPID'
      exec ${lib.getExe pkgs.waypipe} ssh "$1" sh -c "'$remote'"
    '';
    remoteEntry = host: {
      name = "Emacs on ${host}";
      exec = "${lib.getExe emacs-remote} ${host}";
      icon = "emacs";
      categories = ["Development" "TextEditor"];
      terminal = false;
    };
  in {
    # Which emacs build the daemon, wrapper and desktop entries deliver.
    # Defaults to the patched display-independent build; a host wanting
    # stock emacs sets, in its configuration:
    #   home-manager.users.jcmfernandes.jmf.emacs.package = pkgs.emacs-pgtk;
    options.jmf.emacs.package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.emacs-pgtk-headless;
      defaultText = lib.literalExpression "self.packages.<system>.emacs-pgtk-headless";
      description = "The emacs package wrapped and run as the daemon.";
    };

    config = {
      home.packages = [emacs];

      # Attach to the emacs daemon below. `-c` opens a blocking GUI frame (git
      # etc. wait until you finish the buffer); `-a <nano>` falls back to nano
      # if the daemon is somehow down. Never `-a ""` -- that would spawn a
      # rogue daemon. emacsclient comes from the same package the daemon runs
      # -- referencing pkgs.emacs-pgtk would drag a second, stock emacs into
      # the closure just for this one binary. Overrides homeModules.shell's
      # nano default.
      home.sessionVariables.EDITOR = "${config.jmf.emacs.package}/bin/emacsclient -c -a ${lib.getExe pkgs.nano}";
      home.sessionVariables.VISUAL = "${config.jmf.emacs.package}/bin/emacsclient -c -a ${lib.getExe pkgs.nano}";

      # Terminal commands drive the running Emacs when inside a ghostel
      # terminal; oh-my-zsh sources it from its custom dir, which
      # homeModules.shell sets to $XDG_CONFIG_HOME/omz.
      xdg.configFile."omz/emacs.zsh".source = ./shell/emacs.zsh;

      # Emacs as a pgtk daemon owned by systemd, decoupled from whatever launched
      # a frame. Running the *wrapped* emacs so the daemon inherits the compiler
      # and PKG_CONFIG_PATH that straight.el needs for runtime native builds
      # (jinx, tree-sitter). We hand-roll the unit rather than use services.emacs
      # for the same reason emacs.nix avoids programs.emacs: it rebuilds the
      # package via emacsPackagesFor, which rejects the symlinkJoin wrapper.
      systemd.user.services.emacs = {
        Unit = {
          Description = "Emacs daemon (pgtk), wrapped for straight.el native builds";
          # No display coupling, on purpose: emacs-pgtk-headless starts with
          # no compositor running, outlives compositor exits, and attaches
          # frames to whichever display an emacsclient brings along. Paired
          # with users.jcmfernandes.linger, the daemon starts with the
          # machine and depends on no login, graphical or otherwise.
          #
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
          # Terminal frames (emacsclient -t) get their color depth from the
          # *daemon's* environment, captured once at startup -- not from the
          # client's. A systemd-started daemon has no COLORTERM, so every tty
          # frame fell back to 256 colors and approximated the modus palette
          # (modus-vivendi-tinted's #0d0e1c background came out wrong). tmux
          # and the outer terminal already negotiate RGB fine; this was the
          # only missing link.
          Environment = "COLORTERM=truecolor";
          # Signal only emacs on stop, not the whole cgroup. Anything launched
          # from inside emacs -- a podman-compose stack from vterm, say -- is
          # adopted into this unit's cgroup, and the default control-group mode
          # SIGTERMs all of it and then waits out TimeoutStopSec for the cgroup
          # to drain. Containers do not exit on SIGTERM, so logout burned the
          # full 90s in 'stop-sigterm'; meanwhile the queued stop job made every
          # login attempt fail with "Transaction for niri.service/start is
          # destructive (emacs.service has 'stop' job queued)", locking the
          # session out until the timeout expired. process mode ends the unit as
          # soon as emacs itself is gone. The stop duration is then just emacs'
          # own kill-emacs-hook (lsp teardown, claude-code-ide cleanup, session
          # saves), which is work worth waiting for -- so TimeoutStopSec is left
          # alone, now that it only ever bounds emacs.
          KillMode = "process";
        };
        Install.WantedBy = ["default.target"];
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

      # One entry per *other* host running the daemon.
      xdg.desktopEntries.emacs-karma = lib.mkIf (osConfig.networking.hostName != "karma") (remoteEntry "karma");
      xdg.desktopEntries.emacs-anuchka = lib.mkIf (osConfig.networking.hostName != "anuchka") (remoteEntry "anuchka");

      # Hide the emacsclient.desktop that emacs-pgtk ships (via home.packages).
      # It is a bare `emacsclient --alternate-editor=`, so if the systemd daemon
      # is down its empty -a spawns a fresh emacs --daemon in the launcher's
      # cgroup -- the exact rogue-daemon this setup avoids. Same id shadows it.
      xdg.desktopEntries.emacsclient = {
        name = "Emacs (Client)";
        noDisplay = true;
      };

      # Same treatment for the two mail entries emacs-pgtk ships; unused here.
      xdg.desktopEntries.emacs-mail = {
        name = "Emacs (Mail)";
        noDisplay = true;
      };
      xdg.desktopEntries.emacsclient-mail = {
        name = "Emacs (Mail, Client)";
        noDisplay = true;
      };
    };
  };
}
