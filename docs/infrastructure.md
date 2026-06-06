# OpenTofu (cloud infrastructure)

Off-host infrastructure — the Oracle Cloud `vivivi` builder VM and the IONOS
object-storage buckets (nix cache, restic backups, tofu state) — is managed
by OpenTofu under `opentofu/infra/`. Provider credentials and the state
encryption passphrase live in `secrets/infra.yaml` (same sops/age setup as
the host secrets — see [secrets.md](./secrets.md)).

The network access model for the `vivivi` VM (tailscale-only, firewall
deploy ordering, bootstrapping) has its own runbook:
[vivivi.md](./vivivi.md).

## Prerequisites

- YubiKey plugged in, or the backup age key in `age-identities` (see the
  recovery section).
- `direnv allow` once at the repo root and at `opentofu/`; the devenv shell
  provisions `tofu`, `sops`, `age-plugin-yubikey`, etc.

That's it. `opentofu/.envrc` decrypts `secrets/infra.yaml` on direnv load
and exports the three env vars tofu needs: `TF_ENCRYPTION` (state
encryption passphrase), and `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
holding the IONOS S3 keys for the remote state backend (the s3 backend
uses AWS-style env var names regardless of provider).

## Plan / apply

```sh
cd opentofu/infra
tofu plan
tofu apply
```

`tofu init` is only needed after changing the backend block, the encryption
block, or the provider versions.

## What's encrypted at rest

- **Provider secrets** (IONOS API JWT, S3 keys, OCI fingerprint) — in
  `secrets/infra.yaml`, decrypted at plan time by the `carlpett/sops`
  provider via `data "sops_file"`.
- **State and plan files** in the IONOS S3 bucket
  `moreirafernandesdotcom-opentofu-state` — encrypted with PBKDF2 +
  AES-GCM. The passphrase lives in `secrets/infra.yaml` as
  `opentofu_state_passphrase` and gets merged into `TF_ENCRYPTION` by
  `opentofu/.envrc` on direnv load.
- **The `home-infra-backups` bucket** is `prevent_destroy = true` so
  `tofu destroy` won't drop it.

## Rotating the state-encryption passphrase

1. Edit `secrets/infra.yaml` and update `opentofu_state_passphrase`. Keep
   the old value handy.
2. In `versions.tf`, temporarily add a second pbkdf2 key provider and a
   `fallback` block on the `state` / `plan` configs that points at the old
   key (see [OpenTofu key rotation
   docs](https://opentofu.org/docs/language/state/encryption/#key-and-method-rotation)).
3. `tofu apply -refresh-only` — rewrites state with the new passphrase.
4. Remove the fallback block and the old key provider, commit.
