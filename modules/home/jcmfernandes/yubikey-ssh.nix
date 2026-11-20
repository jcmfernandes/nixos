{
  flake.homeModules.yubikey-ssh = {
    lib,
    pkgs,
    ...
  }: let
    # The agent keeps one PIV login for its lifetime; once gpg's scdaemon
    # (homeModules.gpg) switches the card to OpenPGP, every signature fails
    # until the keys are reloaded. The first patch makes libykpiv notice and
    # recover with its cached PIN; it is off unless built with
    # ENABLE_APPLICATION_RECOVERY. The others fix libykpiv's recovery after a
    # card reset. All are pending upstream. Only here: short-lived CLI users
    # don't need them.
    yubico-piv-tool = pkgs.yubico-piv-tool.overrideAttrs (old: {
      patches =
        (old.patches or [])
        ++ [
          ./yubikey-ssh/libykpiv-application-recovery.patch
          ./yubikey-ssh/libykpiv-reset-recovery-failure-cleanup.patch
          ./yubikey-ssh/libykpiv-reset-recovery-keep-failed-pin-attempts.patch
        ];
      env = (old.env or {}) // {NIX_CFLAGS_COMPILE = "-DENABLE_APPLICATION_RECOVERY=1";};
    });
    ykcs11 = "${yubico-piv-tool}/lib/libykcs11.so";
    sshAdd = "${pkgs.openssh}/bin/ssh-add";

    # pick_agent PUBKEY-FILE...: print "SOCKET TYPE BLOB" for the first agent
    # holding one of the given public keys. Agents tried, in order:
    #
    # 1. This ssh session's forwarded agent: it serves the PIV keys from the
    #    machine physically holding the YubiKey.
    # 2. The dedicated local YubiKey agent (the PIV keys aren't in any
    #    default agent).
    # 3. The forwarded agents of my other live ssh sessions, which sshd
    #    drops in ~/.ssh/agent/. Lets programs outside the session (desktop
    #    login, emacs daemon) sign while I'm logged in from the YubiKey's
    #    machine. No new exposure: those sockets are already mine, 0600.
    #
    # -S, not -n: a forwarded socket is session-scoped and vanishes with the
    # session that carried it, so a stale path in the environment is a live
    # possibility (notably under the emacs daemon, which keeps whatever the
    # last client handed it). Requiring an actual socket makes both this and
    # the ssh Match block below fall back rather than aim at a dead path.
    pickAgent = ''
      pick_agent() {
        local s held f type blob _
        for s in ''${SSH_CONNECTION:+"$SSH_AUTH_SOCK"} \
                 "$XDG_RUNTIME_DIR/yubikey-agent.sock" "$HOME"/.ssh/agent/s.*; do
          [ -S "$s" ] || continue
          held=$(SSH_AUTH_SOCK=$s ${sshAdd} -L 2>/dev/null) || continue
          for f in "$@"; do
            [ -r "$f" ] || continue
            read -r type blob _ < "$f"
            case $held in
              *"$blob"*) echo "$s $type $blob"; return 0 ;;
            esac
          done
        done
        return 1
      }
    '';

    # git's gpg.ssh.program and an interactive helper. When signing (-f
    # KEYFILE), points ssh-keygen at the agent pick_agent finds holding that
    # key, so it agrees with yk-signing-key. Otherwise (verification, or no
    # agent holds the key) keeps the old choice: a forwarded agent in this
    # session, else the dedicated YubiKey agent.
    yk-ssh-keygen = pkgs.writeShellScriptBin "yk-ssh-keygen" ''
      ${pickAgent}
      prev="" keyfile=""
      for a in "$@"; do
        [ "$prev" = -f ] && keyfile=$a
        prev=$a
      done
      if [ -n "$keyfile" ] && read -r sock _ < <(pick_agent "$keyfile"); then
        export SSH_AUTH_SOCK=$sock
      elif ! { [ -n "$SSH_CONNECTION" ] && [ -S "$SSH_AUTH_SOCK" ]; }; then
        export SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/yubikey-agent.sock
      fi
      exec ${pkgs.openssh}/bin/ssh-keygen "$@"
    '';

    # git's gpg.ssh.defaultKeyCommand: print the first of the given public
    # keys that an agent holds, so whichever YubiKey is reachable signs.
    #
    # First prunes dead sockets sshd left behind in ~/.ssh/agent/. ssh-agent
    # -u only touches this host's sockets older than an hour, so it can't race
    # a login that is just starting. Silenced: git reads the key from stdout.
    yk-signing-key = pkgs.writeShellScriptBin "yk-signing-key" ''
      ${pkgs.openssh}/bin/ssh-agent -u >/dev/null 2>&1
      ${pickAgent}
      if read -r _ type blob < <(pick_agent "$@"); then
        echo "key::$type $blob"
        exit 0
      fi
      echo "yk-signing-key: no agent holds any of $*" >&2
      exit 1
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
    home.packages = [yk-ssh-keygen yk-signing-key];

    home.file.".ssh/id_ist_yubikey1.pub".source = ./yubikey-ssh/id_ist_yubikey1.pub;
    home.file.".ssh/id_bckground_yubikey1.pub".source = ./yubikey-ssh/id_bckground_yubikey1.pub;
    home.file.".ssh/id_slashid_yubikey1.pub".source = ./yubikey-ssh/id_slashid_yubikey1.pub;
    home.file.".ssh/id_ist_yubikey2.pub".source = ./yubikey-ssh/id_ist_yubikey2.pub;
    home.file.".ssh/id_bckground_yubikey2.pub".source = ./yubikey-ssh/id_bckground_yubikey2.pub;
    home.file.".ssh/id_slashid_yubikey2.pub".source = ./yubikey-ssh/id_slashid_yubikey2.pub;
    home.file.".ssh/allowed_signers".source = ./yubikey-ssh/allowed_signers;

    # The receiving end of forwarding (~/.ssh/rc, multiplexer panes) lives in
    # homeModules.ssh-agent-forwarding, which every host gets.

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
        # After the target: the askpass needs the compositor's display, and
        # an explicit ordering suppresses the target's implicit After= on
        # the units it Wants, which would otherwise invert this.
        After = ["yubikey-ssh-agent.service" "graphical-session.target"];
      };
      Service = {
        Type = "oneshot";
        # The monitor only sees udev add events, and a key plugged in at boot
        # never produces one -- so this also runs at login (WantedBy below),
        # skipping itself unless a Yubico device is already attached.
        ExecCondition = "${pkgs.bash}/bin/sh -c '${pkgs.gnugrep}/bin/grep -qsx 1050 /sys/bus/usb/devices/*/idVendor'";
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
      Install.WantedBy = ["graphical-session.target"];
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

        # Authenticate with the PIV slot-83 key of either YubiKey (ECDSA on
        # the first, Ed25519 on the second), served by the dedicated agent the
        # monitor loads on insert. IdentitiesOnly + the pinned public keys
        # ensure only those keys are offered (the agent holds every
        # retired-slot key); ssh skips whichever isn't plugged in.
        "github.com moon vivivi karma anuchka" = {
          IdentitiesOnly = true;
          IdentityFile = ["~/.ssh/id_ist_yubikey1.pub" "~/.ssh/id_ist_yubikey2.pub"];
          IdentityAgent = "\${XDG_RUNTIME_DIR}/yubikey-agent.sock";
        };

        # Forward the agent to my own hosts -- not github.com, which has no
        # use for it. Without this the PIV keys stop at the first hop: git
        # signing and onward ssh there find a keyless local agent. This is
        # also what makes the Match block above fire on the far side.
        #
        # Multiplexed: later sessions to a host ride the first one's
        # connection. sshd creates one forwarded agent socket per connection,
        # so this stops ~/.ssh/agent/ on the far side filling up with one per
        # login. Also spares the YubiKey a signature per session. %C hashes
        # the path short enough for a unix socket.
        "moon vivivi karma anuchka" = {
          ForwardAgent = true;
          ControlMaster = "auto";
          ControlPath = "~/.ssh/cm-%C";
          ControlPersist = "10m";
        };

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
        signByDefault = true;
        format = "ssh";
        signer = lib.getExe yk-ssh-keygen;
      };
      settings.gpg.ssh = {
        allowedSignersFile = "~/.ssh/allowed_signers";
        # No signing.key: git asks this for the key instead. homeModules.git's
        # per-directory identities override it.
        defaultKeyCommand = "${lib.getExe yk-signing-key} ${./yubikey-ssh/id_ist_yubikey1.pub} ${./yubikey-ssh/id_ist_yubikey2.pub}";
      };
    };
  };
}
