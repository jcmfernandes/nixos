{
  flake.homeModules.git = {
    # The personal gitconfig, ported from the admin machine. Signing
    # machinery (key, signer, allowed signers) lives in
    # homeModules.yubikey-ssh; hm merges both into one config file.
    # Deliberately absent: work includeIf identities and gh credential
    # helpers (no work checkouts and no gh on karma).
    programs.git = {
      enable = true;

      userName = "João Moreira Fernandes";
      userEmail = "joao.fernandes@ist.utl.pt";

      # ~/.gitignore-global equivalent; hm wires core.excludesFile itself.
      ignores = [
        ".aider*"
        "**/.claude/settings.local.json"
        "**/.claude/.cc-writes/"
      ];

      aliases = {
        lol = "log --graph --decorate --pretty=oneline --abbrev-commit";
        lola = "log --graph --date=short --pretty=format:'%C(auto)%h %C(dim)%ad%C(auto)%d %s' --all";
      };

      extraConfig = {
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
