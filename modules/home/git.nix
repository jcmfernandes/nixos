{
  flake.homeModules.git = {
    # The personal gitconfig, ported from the admin machine, including its
    # per-directory work/personal identities (the includeIf files). Signing
    # machinery (key, signer, allowed signers) lives in
    # homeModules.yubikey-ssh; hm merges both into one config file.
    # Deliberately absent: the gh credential helpers (github https is
    # rewritten to ssh below, so they would never fire) and the admin box's
    # stale top-level user.signingkey (id_sign_ist.pub, a dangling path that
    # the own_devel include overrides anyway).
    programs.git = {
      enable = true;

      # ~/.gitignore-global equivalent; hm wires core.excludesFile itself.
      ignores = [
        ".aider*"
        "**/.claude/settings.local.json"
        "**/.claude/.cc-writes/"
      ];

      # Per-directory identities, mirroring the admin machine's includeIf
      # blocks. The matching pubkeys ship via homeModules.yubikey-ssh;
      # gitdirs absent on karma simply never match.
      includes = [
        {
          condition = "gitdir:~/slashid/";
          contents.user = {
            name = "João Moreira Fernandes";
            email = "joao@slashid.dev";
            signingkey = "~/.ssh/id_slashid.pub";
          };
        }
        {
          condition = "gitdir:~/bckground/";
          contents.user = {
            name = "João Moreira Fernandes";
            email = "joao@bckground.com";
            signingkey = "~/.ssh/id_bckground.pub";
          };
        }
        {
          condition = "gitdir:~/own_devel/";
          contents.user = {
            name = "João Moreira Fernandes";
            email = "joao.fernandes@ist.utl.pt";
            signingkey = "~/.ssh/id_ist.pub";
          };
        }
      ];

      settings = {
        user = {
          name = "João Moreira Fernandes";
          email = "joao.fernandes@ist.utl.pt";
        };

        alias = {
          lol = "log --graph --decorate --pretty=oneline --abbrev-commit";
          lola = "log --graph --date=short --pretty=format:'%C(auto)%h %C(dim)%ad%C(auto)%d %s' --all";
        };

        column.ui = "auto";
        branch.sort = "-committerdate";
        tag.sort = "version:refname";
        init.defaultBranch = "main";
        diff = {
          algorithm = "histogram";
          colorMoved = "plain";
          mnemonicPrefix = true;
          renames = true;
        };
        push = {
          default = "simple";
          autoSetupRemote = true;
          followTags = true;
        };
        fetch = {
          prune = true;
          pruneTags = true;
          all = true;
        };
        help.autocorrect = "prompt";
        commit.verbose = true;
        rerere = {
          enabled = true;
          autoupdate = true;
        };
        rebase = {
          autoSquash = true;
          autoStash = true;
          updateRefs = true;
        };
        merge.conflictstyle = "zdiff3";
        sendemail = {
          smtpEncryption = "ssl";
          smtpServer = "mail.tecnico.ulisboa.pt";
          smtpServerPort = 465;
          smtpUser = "ist157885";
        };
        # Route GitHub https remotes through the YubiKey ssh auth.
        url."git@github.com:".insteadOf = "https://github.com/";
      };
    };
  };
}
