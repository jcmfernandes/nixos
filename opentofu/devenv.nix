{pkgs, ...}: {
  packages = with pkgs; [
    opentofu
    terraform-ls
    oci-cli # Oracle Cloud CLI (`oci ...`)
  ];

  enterShell = ''
    echo "$(tofu version | head -n1) ready."
  '';
}
