{
  # The receiving end of agent forwarding: keeps shells on a host you ssh
  # *into* pointed at a live forwarded agent. Belongs on every such host,
  # headless or not -- unlike homeModules.yubikey-ssh, which is about the
  # machine physically holding the YubiKey.
  flake.homeModules.ssh-agent-forwarding = {
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
    #
    # OpenSSH 10.1+ creates forwarded sockets as ~/.ssh/agent/s.*.sshd.*;
    # older servers used /tmp/ssh-*/agent.*. Search both. N: no error when
    # nothing matches; =: sockets only; U: owned by this user; om: newest
    # first, so the most recent live session wins.
    programs.zsh.initContent = ''
      if { [ -n "$TMUX" ] || [ -n "$ZELLIJ" ]; } && [ -n "$SSH_CONNECTION" ]; then
        export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
        _repair_agent_link() {
          [ -S "$SSH_AUTH_SOCK" ] && return
          local s
          for s in $HOME/.ssh/agent/s.*(N=Uom) /tmp/ssh-*/agent.*(N=Uom); do
            ln -sfn "$s" "$SSH_AUTH_SOCK"
            return
          done
        }
        autoload -Uz add-zsh-hook
        add-zsh-hook preexec _repair_agent_link
      fi
    '';
  };
}
