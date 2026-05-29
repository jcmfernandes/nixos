# Secrets management with sops-nix

This repo uses [sops-nix](https://github.com/Mic92/sops-nix) to keep host
secrets encrypted in-tree. Each host has its own encrypted YAML at
`secrets/<host>.yaml`, decrypted at NixOS activation by an age identity
derived from that host's SSH host key.

## Layout

```
.sops.yaml              # recipient list + per-file rules
secrets/
  moon.yaml             # encrypted; one file per host
  <new-host>.yaml       # ...
modules/nixos/hosts/<host>/configuration.nix
                        # imports sops-nix module, declares sops.secrets.*
```

## Recipients (who can decrypt)

Three age identities are listed in `.sops.yaml`. Every secret file is
encrypted to all of them — any single one can decrypt independently.

| Recipient | Lives on | Used for |
|---|---|---|
| `&yubikey` | YubiKey (PIV slot) | Day-to-day editing |
| `&backup` | Paper, in physical safekeeping | Recovery if YubiKey is lost |
| `&moon` (and one per host) | The host's `/etc/ssh/ssh_host_ed25519_key` | Decrypting at NixOS activation |

The YubiKey and the offline backup are the **admin** identities — they let
you (the operator) edit. The host identities are how each machine reads its
own secrets unattended at boot.

## One-time setup on a new admin machine

sops needs to know which YubiKey identities are available locally. Write the
identity stub(s) for every PIV slot the YubiKey holds into
`~/.config/sops/age/keys.txt`:

```sh
mkdir -p ~/.config/sops/age
nix shell nixpkgs#age-plugin-yubikey -c age-plugin-yubikey --identity \
  > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

The contents look like `AGE-PLUGIN-YUBIKEY-1ABCDEF...` — these are **not
secrets**. They're pointers to the YubiKey (device serial + slot). The
private key itself never leaves the device. sops looks at this file
automatically; no env vars needed.

Verify:

```sh
nix shell nixpkgs#age-plugin-yubikey -c age-plugin-yubikey --list
# the listed recipient should match the &yubikey line in .sops.yaml
```

Repeat on every laptop you want to edit secrets from (each laptop's
`keys.txt` is local, never committed).

## Editing secrets

```sh
nix shell nixpkgs#sops nixpkgs#age-plugin-yubikey -c sops secrets/moon.yaml
```

YubiKey must be plugged in; PIN + touch when prompted. After saving, commit
and `nixos-rebuild switch` — sops-nix restarts the units listed under each
secret's `restartUnits`.

## Adding a new host

Say the new host is named `pluto`.

1. **Generate pluto's SSH host key on the admin machine** and stage it
   for upload by `nixos-anywhere`:

   ```sh
   scripts/stage-host-keys.sh pluto
   ```

   The script (a) generates a fresh ed25519 keypair under a `$TMPDIR`
   staging directory laid out as `etc/ssh/ssh_host_ed25519_key{,.pub}`,
   (b) embeds the private key into `secrets/pluto.yaml` as
   `ssh_host_ed25519_key` so an admin (YubiKey + backup) can recover
   pluto's identity if the box ever needs reinstalling, and (c) prints
   the age recipient line plus the remaining manual steps. Doing this
   before install means pluto can decrypt its sops secrets on first
   boot — no re-deploy loop.

   (For a host that's already running and whose host key was generated
   on the machine itself, fetch the pubkey instead:
   `ssh root@pluto cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age`.)

2. **Add it to `.sops.yaml`**:

   ```yaml
   keys:
     - &yubikey age1yubikey1...
     - &backup  age1...
     - &moon    age1scpvuw3...
     - &pluto   age1...        # new

   creation_rules:
     - path_regex: secrets/moon\.yaml$
       age:
         - *yubikey
         - *backup
         - *moon
     - path_regex: secrets/pluto\.yaml$    # new
       age:
         - *yubikey
         - *backup
         - *pluto
   ```

   Each host file lists only the recipients that need access — moon doesn't
   get pluto's secrets, and vice versa.

3. **Create `secrets/pluto.yaml`** with plaintext values, then encrypt:

   ```sh
   nix shell nixpkgs#sops nixpkgs#age-plugin-yubikey -c sops -e -i secrets/pluto.yaml
   ```

   If `secrets/pluto.yaml` already exists and you've just added `&pluto`
   to the creation_rule, re-encrypt it instead:

   ```sh
   sops updatekeys secrets/pluto.yaml
   ```

4. **Wire sops-nix into pluto's configuration**:

   ```nix
   imports = [
     # ...existing imports...
     inputs.sops-nix.nixosModules.sops
   ];

   sops = {
     defaultSopsFile = "${self}/secrets/pluto.yaml";
     age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
     secrets = {
       some_secret = { };
       another_one = {
         owner = "specific-user";        # default is root:root 0400
         mode = "0440";
         restartUnits = [ "foo.service" ];
       };
     };
   };
   ```

   Each declared secret is materialized to `/run/secrets/<name>` at
   activation. Reference it in service config as
   `config.sops.secrets.<name>.path`.

## Rotating keys

### Adding a new admin recipient (e.g. second YubiKey)

```sh
# add the new recipient under `keys:` and to relevant rules in .sops.yaml
nix shell nixpkgs#sops nixpkgs#age-plugin-yubikey -c sops updatekeys secrets/moon.yaml
# repeat for each affected secrets file
git commit -am 'sops: add new admin recipient'
```

`updatekeys` re-encrypts the data key to the new recipient list without
touching the secrets themselves.

### Rotating a host key (host reinstalled)

```sh
ssh root@<host> cat /etc/ssh/ssh_host_ed25519_key.pub \
  | nix shell nixpkgs#ssh-to-age -c ssh-to-age
# replace the host's recipient line in .sops.yaml
nix shell nixpkgs#sops nixpkgs#age-plugin-yubikey -c sops updatekeys secrets/<host>.yaml
git commit -am 'sops: rotate <host> recipient'
nixos-rebuild switch --flake .#<host> --target-host root@<host>
```

### Recovering with the offline backup

If the YubiKey is lost: type the paper-stored `AGE-SECRET-KEY-1...` into a
temporary file, then point sops at it for one editing session:

```sh
mktemp_dir=$(mktemp -d)
${EDITOR:-nano} "$mktemp_dir/keys.txt"   # paste the secret key
SOPS_AGE_KEY_FILE="$mktemp_dir/keys.txt" \
  nix shell nixpkgs#sops -c sops updatekeys secrets/<host>.yaml
shred -u "$mktemp_dir/keys.txt" && rmdir "$mktemp_dir"
```

Then provision a new YubiKey, add its recipient, `updatekeys` again, commit.

## What stays out-of-band

sops won't help with anything needed *before* the NixOS activation script
runs. Per host, that means:

- `/var/lib/luks-keys/*.key` — needed in initrd to unlock encrypted disks.
- `/etc/ssh/ssh_host_ed25519_key` — the host's age identity itself. The
  `scripts/stage-host-keys.sh` flow stashes a copy inside the host's own
  `secrets/<host>.yaml` (encrypted to admin recipients), so an admin can
  re-stage it during a reinstall without breaking decryption of every
  other secret. If you generated the key on the host instead, back it
  up separately or you'll have to `sops updatekeys` everything after a
  reinstall.

## What's NOT a secret (don't put it in sops)

- Public keys, fingerprints, host pubkeys.
- Anything that's already discoverable from outside (DNS records, public
  service ports).

For the gray area — endpoints, bucket names, internal hostnames — it's a
judgment call. They don't grant access on their own, but putting them in
sops adds a layer of "attacker doesn't even know where to look" and avoids
leaking topology in `git log -p`. The trade-off is worse diffs and an extra
indirection at activation. This repo errs on the side of in-sops for
infra-identifying strings (e.g. restic repo URLs).

What you should *not* put in sops: things you want to read or grep
frequently as part of normal development.

## Threat model in one paragraph

The encrypted secrets files in this repo are safe to publish. An attacker
with full read access to the repo learns nothing beyond which secret names
exist per host. Compromise of any single age private key (YubiKey, paper
backup, or one host's SSH host key) decrypts every secret that recipient was
included on. Compromise of an admin identity (YubiKey or backup) decrypts
**everything**. The host identities decrypt only that host's file. There is
no central key server, no network call at decrypt time, no audit log.

# OpenTofu (cloud infrastructure)

Off-host infrastructure — the Oracle Cloud `vivivi` builder VM and the IONOS
object-storage buckets (nix cache, restic backups, tofu state) — is managed
by OpenTofu under `opentofu/infra/`. Provider credentials and the state
encryption passphrase live in `secrets/infra.yaml` (same sops/age setup as
the host secrets above).

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

## vivivi access model — tailscale-only

vivivi has a public OCI IP but it is **firewalled to inbound UDP 41641
only** (tailscale's WireGuard port). Everything else — SSH, the attic
binary cache on 8080, future services — is reachable **only through
the tailnet** (`tailscale0` is a trusted interface, so the NixOS firewall
doesn't block traffic arriving on it). Two defenses are stacked:

- **OCI security list** (`opentofu/infra/builder.tf`,
  `oci_core_security_list.vivivi`): the only `ingress_security_rule` is
  UDP 41641 from `0.0.0.0/0`. Egress is unrestricted (tailscale's
  control-plane + DERP relay traffic to `*.tailscale.com` and DERP
  nodes needs that).
- **NixOS firewall** (`modules/nixos/hosts/vivivi/configuration.nix`):
  `firewall.allowedTCPPorts = []`. `services.tailscale.openFirewall`
  (default `true`) adds the UDP 41641 hole and the trusted-interface
  rule for `tailscale0`.

### Reaching vivivi

```sh
# Via MagicDNS (any tailnet member):
ssh jcmfernandes@vivivi

# Or by tailscale IP if MagicDNS isn't configured:
tailscale status | awk '/vivivi/ {print $1}'
ssh jcmfernandes@<that-100.x.x.x>
```

The public IP is intentionally **not** an access path. If tailscale on
vivivi breaks (e.g. authkey rotation gone wrong, daemon crash), recovery
goes through the OCI serial console — see the broader OCI debugging
section of the OCI docs or use:

```sh
# from opentofu/, with oci-config + oci.pem extracted from sops:
oci compute instance-console-connection create \
  --instance-id <vivivi-ocid> \
  --ssh-public-key-file console-rsa.pub
```

(generate `console-rsa.pub` once via
`ssh-keygen -t rsa -b 2048 -f console-rsa -N ''`; OCI rejects ed25519
for console connections.)

### Deploy order when changing the firewall

Both layers can be changed at any time, but the **order matters** when
tightening (loosening is always safe):

1. **First** confirm tailscale access to vivivi works
   (`ssh jcmfernandes@vivivi` from a tailnet member returns a prompt).
2. **Then** `tofu apply` the OCI security-list change.
3. **Then** `nixos-rebuild switch --flake .#vivivi --target-host
   root@vivivi --build-host root@vivivi` to land the NixOS-side
   firewall.

If you skip step 1 and the apply in step 2 closes public-IP SSH while
tailscale isn't yet reachable, the only recovery is the OCI serial
console.

### Bootstrapping a fresh vivivi (or recreating it)

The steady-state firewall above has a chicken-and-egg problem when the
instance is *first* provisioned (or recreated): the fresh OCI image is
plain Ubuntu without tailscale installed, so the only inbound it can
accept is SSH-22 — which the security list normally blocks.

There's a **commented-out `ingress_security_rules` block for TCP 22**
in `opentofu/infra/builder.tf` for exactly this case. Workflow:

1. Uncomment the TCP-22 block (restricted to `var.ssh_allowed_cidr`).
2. `tofu apply` to open the hole.
3. `tofu apply -replace=oci_core_instance.vivivi` (or the initial
   `tofu apply` if you're provisioning from zero).
4. Run `nixos-anywhere` against the fresh Ubuntu instance over SSH-22
   (see the install runbook elsewhere).
5. Once vivivi has booted into NixOS and tailscale has registered with
   the tailnet, **re-comment the TCP-22 block** and `tofu apply` again
   to close the hole. From this point on, day-to-day access is
   tailnet-only as described above.

Skipping step 5 leaves the public IP accepting SSH long after vivivi
has tailscale-based access — the auth is still key-based so it's not a
disaster, but it widens the attack surface vivivi was specifically set
up to avoid.
