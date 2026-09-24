# AGENTS.md

This file provides guidance to agentic tools when working with code in this
repository. The project overview, build/deploy commands, and dev shell are
in the README, imported here: @README.md

Deep-dive runbooks live in `docs/` (secrets, infrastructure, vivivi access
model) and in per-host READMEs (`modules/nixos/hosts/<host>/README.md`).

## Dev environment notes

- `.envrc` exports `SOPS_AGE_KEY_FILE=$PWD/age-identities` so sops can
  decrypt using the YubiKey-backed identity stub.
- `opentofu/` has its **own** separate `devenv`/`.envrc` — run `direnv allow`
  there too before touching infrastructure (see `docs/infrastructure.md`).
- Pre-commit hooks (devenv git-hooks) enforce alejandra, statix, shellcheck,
  and gitleaks on staged files.

## Common commands

```sh
# Format / lint Nix (both also run as pre-commit hooks)
nix fmt                              # alejandra, wired as the flake formatter
statix check                         # lint (in the dev shell)

# Evaluate the whole flake (build all nixosConfigurations, run checks)
nix flake check

# Build a host config without deploying
nixos-rebuild build --flake .#<host>     # host ∈ {karma, moon, vivivi}

# Scan git history for leaked secrets
gitleaks detect --source . --config .gitleaks.toml --redact -v
```

Deploy commands are in the README. When staging the flake to a remote host,
use `scripts/scp-flake.sh <ssh-target>` — never `scp -r .` or rsync: the
script streams only the git-tracked/staged/dirty files over ssh (via tar),
deliberately excluding `.git/`, `.direnv/`, `opentofu/` state, and the
plaintext `age-identities`.

Fresh installs use `nixos-anywhere` + `disko` (each host has a
`disko.nix`); the sops side of adding a host is in `docs/secrets.md`.

## Architecture

### flake-parts + import-tree (no central module list)

`flake.nix` imports `(import-tree ./modules)` — **every `.nix` file under
`modules/` is auto-discovered and evaluated as a flake-parts module.** There
is no hand-maintained import list; adding a file under `modules/` wires it
in. `modules/parts.nix` pins `systems = ["x86_64-linux"]` and declares the
custom `flake.homeModules` option.

Files contribute to the flake by *setting attributes*, not by being
imported by name:

- `flake.nixosModules.<name> = { ... }` — a reusable NixOS module (e.g.
  `base`, `persistenceDefaults`, `desktop`, `nix`, and per-host `<host>Configuration` /
  `<host>Hardware`).
- `flake.homeModules.<name>` — a reusable Home Manager module (e.g.
  `yubikey-ssh`, `git`), consumed via `home-manager.users.<user>.imports`
  in the user's NixOS module (`modules/nixos/users/<user>/`).
- `flake.theme` / `flake.themeNoHash` — the gruvbox base16 palette
  (`modules/theme.nix`), consumed as `self.theme.baseNN` by home modules.

Because flake-parts merges modules, **several files extend the same
`flake.nixosModules.base`**: `base/base.nix` adds `options.preferences`,
`base/persistence.nix` adds `options.persistence`. Don't expect one file to
hold a module's full definition.

### Hosts

Each host lives in `modules/nixos/hosts/<host>/`:

- `default.nix` declares `flake.nixosConfigurations.<host>` by calling
  `nixosSystem` with `self.nixosModules.<host>Configuration` in its module
  list.
- `configuration.nix` *defines* `flake.nixosModules.<host>Configuration`,
  which `imports` the shared `self.nixosModules.{base,persistenceDefaults,desktop,...}`,
  disko, and `inputs.sops-nix.nixosModules.sops`, then declares
  `sops.secrets.*`.

The four hosts differ significantly:

- **karma** — x86_64 desktop (niri/Wayland). Plain `nixpkgs.lib.nixosSystem`.
- **moon** — Raspberry Pi 5 media server (aarch64). Built via
  `nixos-raspberrypi` (needs `inject-overlays` for the Pi kernel/firmware)
  and pinned to stable nixpkgs (`nixos-26.05`) -- `nixos-raspberrypi` itself
  pins its nixpkgs to 26.05, which makes stable the aligned channel choice.
  Runs `nixarr` (Sonarr/Radarr/etc.), Immich, and nightly restic backups to
  IONOS S3 — see `modules/nixos/hosts/moon/README.md` for the backup/restore
  runbook. Requires an explicit `fileSystems."/boot/firmware"` mount or
  rebuilds silently write to an ext4 shadow and the Pi boots a stale gen.
- **vivivi** — Oracle Cloud builder VM. **Tailnet-only access** (public IP
  firewalled to UDP 41641); built remotely (`--build-host`). Provisioned by
  OpenTofu. See `docs/vivivi.md` before changing any firewall — deploy
  ordering matters or you lock yourself out.
- **anuchka** — x86_64 AMD laptop (niri/Wayland), same desktop stack as
  karma minus multi-monitor plumbing and the UPS module. Single-screen,
  disko-installed like karma, Secure Boot staged (off by default), no UPS.

### Shell & GUI configuration (home-manager)

The interactive shell is plain zsh: `homeModules.shell` sets
`programs.zsh` (mise activation, EDITOR -- nano by default, emacsclient
where `homeModules.emacs` is present) and puts the CLI toolchain on the
user's PATH via `home.packages`. It is the login shell on every host.

The user is split in two NixOS modules under
`modules/nixos/users/jcmfernandes/`:

- `nixosModules.jcmfernandes` (`default.nix`) -- the account and
  `homeModules.cli`, a bundle of the display-free home modules (shell,
  git, tmux, zellij, mise, ssh-agent-forwarding). **All four hosts**
  import it; nothing in it may need a display.
- `nixosModules.jcmfernandesDesktop` (`desktop.nix`) -- device groups and
  the GUI home modules. karma and anuchka import it on top.

GUI configuration (niri, kitty, wlr-which-key, GTK theming, fonts,
desktop apps, flatpaks, emacs, firefox, the YubiKey agent) lives in Home
Manager modules under `modules/home/jcmfernandes/`
(`flake.homeModules.*`), consumed via the desktop module. The niri
home module renders its settings with `BirdeeHub/nix-wrapper-modules`'
`evalModule`/`toKdl` (validated with `niri validate` at build time)
and delivers the result as `~/.config/niri/config.kdl` for plain
`pkgs.niri` to read.

### Secrets (sops-nix) — see docs/secrets.md

`docs/secrets.md` is the authoritative runbook for secrets. Key facts:

- Per-host encrypted YAML at `secrets/<host>.yaml`; recipients/rules in
  `.sops.yaml`. Each file is encrypted to the admin YubiKey, an offline
  paper backup, **and** that host's SSH-host-key-derived age identity (how
  the host decrypts unattended at activation).
- Edit with `sops secrets/<host>.yaml` (YubiKey + PIN + touch). After
  changing `.sops.yaml` recipients, run `sops updatekeys secrets/<host>.yaml`.
- Declared secrets materialize at `/run/secrets/<name>`; reference as
  `config.sops.secrets.<name>.path`. `restartUnits` restarts consumers on
  change.
- `.gitleaks.toml` allowlists `secrets/*.yaml` (ciphertext) and
  `age-identities` (a hardware-backed stub, not extractable key material).

### Cloud infrastructure (`opentofu/infra/`) — see docs/infrastructure.md

OpenTofu manages the OCI `vivivi` VM and IONOS S3 buckets (nix cache,
restic backups, tofu state). Provider creds and the state-encryption
passphrase come from `secrets/infra.yaml` via the `carlpett/sops` provider
and `opentofu/.envrc`. Work from `opentofu/infra/`: `tofu plan` / `tofu
apply` (`tofu init` only after backend/encryption/provider-version
changes).
