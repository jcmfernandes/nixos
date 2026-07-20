# NixOS Configuration & IaC

My personal NixOS configuration — a [flake](https://nixos.wiki/wiki/Flakes)
managing every machine I run, the secrets they need, and the cloud
infrastructure that supports them.

The flake uses [flake-parts](https://flake.parts) with
[import-tree](https://github.com/vic/import-tree): there is no central import
list — every `.nix` file under `modules/` is discovered automatically.

## Building & deploying

```sh
# Build/deploy a host locally
sudo nixos-rebuild switch --flake .#<host>

# Deploy to a remote host (stage the flake first, then rebuild there)
scripts/scp-flake.sh root@<host>
ssh root@<host> 'nixos-rebuild switch --flake /etc/nixos#<host>'

# ...or without copying anything: evaluate here, push the closure over ssh
nixos-rebuild switch -S --flake .#<host> --target-host root@<host>
```

The staged-flake route leaves a working copy at `/etc/nixos` so the host can
rebuild itself; `--target-host` doesn't. Add `--build-host root@<host>` to
either to build on the target — required in practice for moon, which is
aarch64.

`direnv allow` at the repo root drops you into a `devenv` shell with the
tooling (`sops`, `age-plugin-yubikey`, `nixos-anywhere`, `gitleaks`, …).
