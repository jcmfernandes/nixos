{pkgs, ...}: {
  packages = with pkgs; [
    opentofu
    terraform-ls
    oci-cli # Oracle Cloud CLI (`oci ...`)
    jq # .envrc: pick values out of the decrypted infra.yaml
  ];

  enterShell = ''
    echo "$(tofu version | head -n1) ready."
  '';
}
