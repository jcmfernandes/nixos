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

1. **Get pluto's SSH host pubkey as an age recipient** (after pluto has been
   installed at least once so its host key exists):

   ```sh
   ssh root@pluto cat /etc/ssh/ssh_host_ed25519_key.pub \
     | nix shell nixpkgs#ssh-to-age -c ssh-to-age
   ```

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
- `/etc/ssh/ssh_host_ed25519_key` — the host's age identity itself. Back it
  up separately if you want a freshly-installed host to decrypt existing
  secrets without a re-encrypt step.

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
