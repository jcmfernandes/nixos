{
  flake.homeModules.yubikey-ssh = {
    lib,
    pkgs,
    ...
  }: let
    ykcs11 = "${pkgs.yubico-piv-tool}/lib/libykcs11.so";
    sshAdd = "${pkgs.openssh}/bin/ssh-add";

    # git's gpg.ssh.program and an interactive helper. Points SSH
    # signing/verification at the dedicated YubiKey ssh-agent (the PIV keys
    # aren't in any default agent).
    #
    # Exception: in an ssh session carrying a forwarded agent, that agent
    # already serves the PIV keys from the machine physically holding the
    # YubiKey, while this host's yubikey-agent.sock is keyless and refuses
    # every signature -- so honour the inherited socket there.
    #
    # -S, not -n: the forwarded socket is session-scoped and vanishes with the
    # session that carried it, so a stale path in the environment is a live
    # possibility (notably under the emacs daemon, which keeps whatever the
    # last client handed it). Requiring an actual socket makes both this and
    # the ssh Match block below fall back rather than aim at a dead path.
    yk-ssh-keygen = pkgs.writeShellScriptBin "yk-ssh-keygen" ''
      if [ -n "$SSH_CONNECTION" ] && [ -S "$SSH_AUTH_SOCK" ]; then
        exec ${pkgs.openssh}/bin/ssh-keygen "$@"
      fi
      exec env SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR}/yubikey-agent.sock" ${pkgs.openssh}/bin/ssh-keygen "$@"
    '';

    yubikey-usb-monitor = pkgs.writeShellApplication {
      name = "yubikey-usb-monitor";
      runtimeInputs = [pkgs.systemd];
      text = ''
        # Watch udev (as the user, no root) for Yubico (idVendor 1050) USB
        # device add/remove events. On insert, load the PKCS#11 keys into
        # the dedicated ssh-agent (prompts for the PIN); on removal, flush
        # that agent.
        #
        # --property prints each event as a block of KEY=VALUE lines
        # terminated by a blank line; we accumulate the fields we care
        # about and act at the blank line.
        #
        # Two ways to recognise the vendor, because they are not equally
        # available. ID_VENDOR_ID is synthesised by udev's usb_id builtin,
        # which runs while the device exists -- on `remove` it is often
        # absent, so matching on it alone saw every insert and no removal,
        # leaving the agent listing keys whose card was long gone. PRODUCT
        # (idVendor/idProduct/bcdDevice, lowercase hex) comes straight from
        # the kernel uevent and is present on both. DEVTYPE is kernel-side
        # too, and keeps this to the device rather than its interfaces.
        action=""
        vid=""
        product=""
        devtype=""

        udevadm monitor --udev --property --subsystem-match=usb |
          while IFS= read -r line; do
            case "$line" in
              ACTION=*) action=''${line#ACTION=} ;;
              ID_VENDOR_ID=*) vid=''${line#ID_VENDOR_ID=} ;;
              PRODUCT=*) product=''${line#PRODUCT=} ;;
              DEVTYPE=*) devtype=''${line#DEVTYPE=} ;;
              "") # end of one event block
                if [ "$devtype" = "usb_device" ] &&
                  { [ "$vid" = "1050" ] || [ "''${product%%/*}" = "1050" ]; }; then
                  case "$action" in
                    add) systemctl --user --no-block start yubikey-ssh-add.service ;;
                    remove) systemctl --user --no-block start yubikey-ssh-flush.service ;;
                  esac
                fi
                action=""
                vid=""
                product=""
                devtype=""
                ;;
            esac
          done
      '';
    };
  in {
    home.packages = [yk-ssh-keygen];

    home.file.".ssh/id_ist.pub".source = ./yubikey-ssh/id_ist.pub;
    home.file.".ssh/id_bckground.pub".source = ./yubikey-ssh/id_bckground.pub;
    home.file.".ssh/id_slashid.pub".source = ./yubikey-ssh/id_slashid.pub;
    home.file.".ssh/allowed_signers".source = ./yubikey-ssh/allowed_signers;

    # A tmux/zellij pane's shell keeps the SSH_AUTH_SOCK of the connection that
    # spawned it; once that connection drops, the path is dead and a
    # reattach can't fix it. sshd runs ~/.ssh/rc on every login, so repoint
    # a stable link at the current forwarded socket there, and have shells
    # inside a multiplexer use the link instead. Not elsewhere: a direct login
    # shell's own socket outlives the link whenever a newer session closes.
    home.file.".ssh/rc".text = ''
      if [ -S "$SSH_AUTH_SOCK" ]; then
        ln -sfn "$SSH_AUTH_SOCK" "$HOME/.ssh/agent.sock"
      fi
    '';
    #
    # The link tracks the newest login, so it dies with it even while older
    # connections live on -- including a seconds-long git/rsync one. Before
    # each command, repoint a dead link at any forwarded socket still alive.
    programs.zsh.initContent = ''
      if { [ -n "$TMUX" ] || [ -n "$ZELLIJ" ]; } && [ -n "$SSH_CONNECTION" ]; then
        export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
        _repair_agent_link() {
          [ -S "$SSH_AUTH_SOCK" ] && return
          local s
          for s in /tmp/ssh-*/agent.*(NU=); do
            ln -sfn "$s" "$SSH_AUTH_SOCK"
            return
          done
        }
        autoload -Uz add-zsh-hook
        add-zsh-hook preexec _repair_agent_link
      fi
    '';

    systemd.user.services.yubikey-ssh-agent = {
      Unit.Description = "Dedicated ssh-agent holding YubiKey PKCS#11 keys";
      Service = {
        Type = "simple";
        ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %t/yubikey-agent.sock";
        # -P: ssh-agent's default PKCS#11 allowlist is /usr/lib*, which
        # silently rejects nix store paths. ssh-add canonicalizes the
        # provider with realpath before the agent's whitelist check, and
        # libykcs11.so is a symlink to the versioned soname
        # (libykcs11.so.2.7.3), so the pattern must end in '.so*' to match
        # the resolved path -- ending it at '.so' refuses every load. The
        # leading glob (not the exact store hash) also tolerates ssh-add
        # vs. agent skew across a rebuild.
        ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a %t/yubikey-agent.sock -P '/nix/store/*/lib/libykcs11.so*'";
        Restart = "on-failure";
      };
      Install.WantedBy = ["default.target"];
    };

    systemd.user.services.yubikey-monitor = {
      Unit = {
        Description = "Watch for YubiKey insert/removal and (un)load its ssh-agent keys";
        Wants = ["yubikey-ssh-agent.service"];
        After = ["yubikey-ssh-agent.service"];
      };
      Service = {
        Type = "simple";
        ExecStart = lib.getExe yubikey-usb-monitor;
        Restart = "always";
        RestartSec = 2;
      };
      Install.WantedBy = ["default.target"];
    };

    systemd.user.services.yubikey-ssh-add = {
      Unit = {
        Description = "Load YubiKey PKCS#11 keys into the dedicated agent (prompts for PIN)";
        Requires = ["yubikey-ssh-agent.service"];
        After = ["yubikey-ssh-agent.service"];
      };
      Service = {
        Type = "oneshot";
        Environment = [
          "SSH_AUTH_SOCK=%t/yubikey-agent.sock"
          "SSH_ASKPASS=${pkgs.lxqt.lxqt-openssh-askpass}/bin/lxqt-openssh-askpass"
          "SSH_ASKPASS_REQUIRE=force"
        ];
        # Drop any stale instance of the module first (ignore failure),
        # then (re)load -- the load is what pops the PIN prompt.
        ExecStart = [
          "-${sshAdd} -e ${ykcs11}"
          "${sshAdd} -s ${ykcs11}"
        ];
      };
    };

    systemd.user.services.yubikey-ssh-flush = {
      Unit.Description = "Flush the dedicated YubiKey ssh-agent when the key is removed";
      Service = {
        Type = "oneshot";
        Environment = ["SSH_AUTH_SOCK=%t/yubikey-agent.sock"];
        ExecStart = "-${sshAdd} -D";
      };
    };

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        # Same exception as yk-ssh-keygen: over a forwarded agent the pinned
        # socket below is keyless and refuses to authenticate, so let the
        # inherited SSH_AUTH_SOCK win. First-obtained-value-wins means this
        # block only has to override IdentityAgent -- IdentitiesOnly and
        # IdentityFile still come from the block after it.
        #
        # Note the comma-separated host list: `Match host` takes a
        # pattern-list, unlike `Host`, which is space-separated.
        #
        # Both conditions are load-bearing. SSH_CONNECTION alone is not
        # enough: without a usable socket this block still wins and resolves
        # IdentityAgent to nothing, at which point ssh falls back to reading
        # the *public* key as a private one and dies with "error in
        # libcrypto: unsupported" -- worse than never having matched. And a
        # socket alone is not enough either, because a local session's
        # SSH_AUTH_SOCK (gnome-keyring's gcr/ssh) is a perfectly good socket
        # that holds none of the PIV keys.
        forwarded-agent = lib.hm.dag.entryBefore ["github.com moon vivivi karma anuchka"] {
          header = ''Match host github.com,moon,vivivi,karma,anuchka exec "test -n \"$SSH_CONNECTION\" && test -S \"$SSH_AUTH_SOCK\""'';
          IdentityAgent = "SSH_AUTH_SOCK";
        };

        # Authenticate with the YubiKey PIV slot-83 key (ECDSA), served by
        # the dedicated agent the monitor loads on insert. IdentitiesOnly +
        # the pinned public key ensure exactly that key is offered (the agent
        # holds all four retired-slot keys).
        "github.com moon vivivi karma anuchka" = {
          IdentitiesOnly = true;
          IdentityFile = "~/.ssh/id_ist.pub";
          IdentityAgent = "\${XDG_RUNTIME_DIR}/yubikey-agent.sock";
        };

        # Forward the agent to my own hosts -- not github.com, which has no
        # use for it. Without this the PIV keys stop at the first hop: git
        # signing and onward ssh there find a keyless local agent. This is
        # also what makes the Match block above fire on the far side.
        "moon vivivi karma anuchka".ForwardAgent = true;

        # This terminal's TERM (xterm-ghostty) has no terminfo entry on
        # either host, so anything curses-based there renders as garbage.
        # Send a TERM they do know instead. ssh normally takes TERM from the
        # local environment for the pty request; SetEnv overrides that.
        "moon vivivi".SetEnv.TERM = "xterm-256color";
      };
    };

    # Signing machinery only; identity/ergonomics live in homeModules.git.
    programs.git = {
      signing = {
        key = "~/.ssh/id_ist.pub";
        signByDefault = true;
        format = "ssh";
        signer = lib.getExe yk-ssh-keygen;
      };
      settings.gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
    };
  };
}
