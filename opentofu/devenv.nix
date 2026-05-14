{ pkgs, ... }: {
  packages = with pkgs; [
    opentofu
    terraform-ls
  ];

  enterShell = ''
    echo "$(tofu version | head -n1) ready."
  '';
}
