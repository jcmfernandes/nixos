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
    yk-ssh-keygen = pkgs.writeShellScriptBin "yk-ssh-keygen" ''
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
        action=""
        vid=""
        devtype=""

        udevadm monitor --udev --property --subsystem-match=usb |
          while IFS= read -r line; do
            case "$line" in
              ACTION=*) action=''${line#ACTION=} ;;
              ID_VENDOR_ID=*) vid=''${line#ID_VENDOR_ID=} ;;
              DEVTYPE=*) devtype=''${line#DEVTYPE=} ;;
              "") # end of one event block
                if [ "$vid" = "1050" ] && [ "$devtype" = "usb_device" ]; then
                  case "$action" in
                    add) systemctl --user --no-block start yubikey-ssh-add.service ;;
                    remove) systemctl --user --no-block start yubikey-ssh-flush.service ;;
                  esac
                fi
                action=""
                vid=""
                devtype=""
                ;;
            esac
          done
      '';
    };
  in {
    home.packages = [yk-ssh-keygen];

    home.file.".ssh/id_ist.pub".source = ./yubikey-ssh/id_ist.pub;
    home.file.".ssh/allowed_signers".source = ./yubikey-ssh/allowed_signers;

    systemd.user.services.yubikey-ssh-agent = {
      Unit.Description = "Dedicated ssh-agent holding YubiKey PKCS#11 keys";
      Service = {
        Type = "simple";
        ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %t/yubikey-agent.sock";
        # -P: ssh-agent's default PKCS#11 allowlist is /usr/lib*, which
        # silently rejects nix store paths. The glob (not the exact store
        # path) tolerates skew between a long-running agent and a newer
        # ssh-add after a rebuild.
        ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a %t/yubikey-agent.sock -P '/nix/store/*/lib/libykcs11.so'";
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
      # Authenticate with the YubiKey PIV slot-83 key (ECDSA), served by
      # the dedicated agent the monitor loads on insert. IdentitiesOnly +
      # the pinned public key ensure exactly that key is offered (the agent
      # holds all four retired-slot keys).
      matchBlocks."github.com moon vivivi" = {
        identitiesOnly = true;
        identityFile = "~/.ssh/id_ist.pub";
        extraOptions.IdentityAgent = "\${XDG_RUNTIME_DIR}/yubikey-agent.sock";
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
      extraConfig.gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
    };
  };
}
