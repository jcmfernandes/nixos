{self, ...}: {
  # The shell experience for any host, graphical or not: zsh/oh-my-zsh/
  # starship/zoxide plus the CLI toolchain, the configs for the tools that
  # ship with it, and the receiving end of agent forwarding. Nothing here
  # needs a display.
  #
  # Hosts get this through nixosModules.jcmfernandes; graphical hosts add
  # nixosModules.jcmfernandesDesktop on top.
  flake.homeModules.cli = {
    imports = [
      self.homeModules.shell
      self.homeModules.git
      self.homeModules.tmux
      self.homeModules.zellij
      self.homeModules.mise
      self.homeModules.ssh-agent-forwarding
    ];
  };
}
