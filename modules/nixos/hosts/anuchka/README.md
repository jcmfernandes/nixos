# anuchka — AMD laptop

anuchka is a personal AMD laptop that mirrors karma's desktop: niri/Wayland,
the noctalia bar, gruvbox theming, and the shared `jcmfernandes` Home Manager
stack. It differs from karma in three deliberate ways — it is single-screen
(no multi-monitor plumbing), it has no UPS, and it imports the `laptop` feature
module (power-profiles-daemon, fwupd, brightnessctl).

Storage is the same as karma: disko lays out GPT → 1 G ESP + LUKS (`cryptroot`)
→ LVM (`pool`) → btrfs (zstd, noatime). The only difference is the target
device: **`/dev/nvme0n1`** (`disko.nix`, `mkDefault`). Everything referenced at
boot is on-disk (partlabel/LVM/UUID), so the layout is bus-agnostic.

Networking mirrors karma: tailnet-only (the LAN NIC is fully closed;
`tailscale0` is the only trusted interface), plus a njalla DDNS record
`anuchka.hosts.moreirafernandes.com` publishing the tailscale IP.

## Prerequisites

- The repo's devenv shell active (`direnv allow` at the repo root) — provides
  `nixos-anywhere`, `sops`, `ssh-to-age`, `SOPS_AGE_KEY_FILE`.
- YubiKey plugged in (needed to encrypt anuchka's secrets).
- A NixOS **minimal x86_64 ISO** to boot the laptop from (USB stick).

## Step 0 — Create anuchka's secrets (one-time, required before any build)

anuchka is a **new** host, so it needs its own sops file and recipient. Until
`secrets/anuchka.yaml` exists, the flake will not build (both
`sops.secrets.*.sopsFile` reference it). Follow `docs/secrets.md`'s
"Adding a new host":

1. **Add a creation rule first** — `stage-host-keys.sh` writes an *encrypted*
   `secrets/anuchka.yaml`, so `.sops.yaml` must already match it or sops errors
   with `no matching creation rules found`. The host's own recipient isn't
   known until step 2 generates the key, so seed the rule with just the admin
   recipients for now:

   ```yaml
   creation_rules:
     # ...
     - path_regex: secrets/anuchka\.yaml$
       age:
         - *yubikey
         - *backup
   ```

2. **Stage a fresh host key** (generates the keypair, embeds the private key
   into `secrets/anuchka.yaml` for admin recovery, and prints anuchka's age
   recipient):

   ```sh
   scripts/stage-host-keys.sh anuchka
   ```

   Keep the staging directory it prints — you'll pass it to `nixos-anywhere`
   in Step 2 so the host key lands before the first sops activation.

3. **Add anuchka as a recipient** — add the printed `&anuchka age1…` line under
   `keys:` in `.sops.yaml` and reference it (`- *anuchka`) in the creation rule
   from step 1, then re-key so the host can decrypt its own file:

   ```sh
   sops updatekeys secrets/anuchka.yaml
   ```

4. **Fill in the secret values.** `secrets/anuchka.yaml` (already encrypted,
   holding the host key) also needs:
   - `tailscale_authkey` — a tailnet auth key (reusable/ephemeral as you
     prefer).
   - `njalla_ddns_env` — `DDNS_KEY=<njalla update key for the DDNS record>`.

   ```sh
   sops secrets/anuchka.yaml
   ```

5. **Confirm the flake now evaluates:**

   ```sh
   nixos-rebuild build --flake .#anuchka
   ```

## Step 1 — Boot the installer on the laptop

Flash the NixOS minimal ISO to a USB stick, boot the laptop from it (UEFI, with
Secure Boot **off** in firmware — the bootloader is unsigned until you arm
lanzaboote later). Then, on the laptop:

```sh
sudo passwd root          # set a temporary root password for the install
lsblk                     # confirm the target NVMe is /dev/nvme0n1
ip -4 addr                # note the laptop's LAN IP
```

> If the NVMe enumerates as something other than `/dev/nvme0n1`, either pass
> `--disko-mode` overrides or set `disko.devices.disk.disk1.device` for this
> run — the `mkDefault` in `disko.nix` lets the install-time value win.

## Step 2 — Install with nixos-anywhere

From the repo root on the admin machine (x86_64 → builds locally):

```sh
nixos-anywhere --extra-files "$staging" --flake .#anuchka root@<laptop-ip>
```

- `--extra-files "$staging"` overlays the staged host key onto the target's
  `/` (at `/etc/ssh/ssh_host_ed25519_key`) **before** the first sops-nix
  activation, so tailscale/njalla decrypt on first boot.
- Accept the host fingerprint; enter the temporary root password when asked.
- disko **wipes `/dev/nvme0n1`** and prompts for the **LUKS passphrase** —
  choose one you'll remember; you'll type it at every boot until (optionally)
  you enroll TPM2/FIDO2.

When it finishes the laptop reboots into anuchka. **Shred the staged key**
afterwards — it holds a plaintext private key:

```sh
shred -u "$staging/etc/ssh/ssh_host_ed25519_key" && rm -rf "$staging"
```

## Step 3 — Refine the hardware profile (recommended)

`hardware.nix` ships a generic AMD/NVMe baseline (all `mkDefault`). On the
installed machine, generate the real profile and reconcile any differences
(extra initrd modules, firmware):

```sh
sudo nixos-generate-config --no-filesystems --show-hardware-config
```

Merge anything new into `modules/nixos/hosts/anuchka/hardware.nix`. Skip the
`fileSystems`/`swapDevices` it emits — disko and `configuration.nix` own those.

## Day-to-day deploy

```sh
sudo nixos-rebuild switch --flake .#anuchka          # on the laptop
# or, over the tailnet from the admin machine:
scripts/scp-flake.sh root@anuchka
ssh root@anuchka 'nixos-rebuild switch --flake /etc/nixos#anuchka'
```

## Arming Secure Boot + TPM2 auto-unlock

anuchka imports the shared `secureboot` module **staged/off** exactly like
karma (`boot.lanzaboote.enable` defaults to `false`; systemd-boot stays the
bootloader and `sbctl` is available). Arming is a deliberate, on-hardware step.
The procedure is identical to karma's — see the "Arming Secure Boot + TPM2
auto-unlock" section of `modules/nixos/hosts/karma/README.md`. anuchka's LUKS
partition is `/dev/disk/by-partlabel/disk-disk1-root` (same disko structure).
A laptop generally has a TPM2 chip, so the TPM2 auto-unlock step applies.

## Optional — YubiKey (FIDO2) LUKS unlock

LUKS2 has multiple keyslots, so a YubiKey can be added as a second slot with
the passphrase kept as fallback. Do it on the machine (FIDO2 needs the key
present):

```sh
# systemd initrd is the 26.05 default; enroll a FIDO2 slot:
sudo systemd-cryptenroll --fido2-device=auto /dev/disk/by-partlabel/disk-disk1-root
```

Keep at least the passphrase slot as recovery.
