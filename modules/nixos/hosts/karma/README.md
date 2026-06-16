# Installing karma into a VM backed by a physical NVMe SSD

This runbook installs karma onto a **physical NVMe SSD** by handing that disk
to a throwaway installer VM (raw block passthrough via virt-manager), running
`nixos-anywhere`, and then moving the SSD into the real machine to boot it.

karma is already built to run as a VM — its hardware profile imports
`qemu-guest.nix` and only loads virtio block modules — so this is its natural
install path, not a workaround.

## Why this works (the short version)

- **karma's disko targets `/dev/vda`** (`disko.nix`): full-disk GPT → ESP +
  LUKS → LVM → btrfs (UEFI-only; no BIOS-boot partition). Whatever disk the
  guest sees as `/dev/vda` gets wiped and becomes karma's root. Expose the
  NVMe as a **VirtIO** disk and it appears as `/dev/vda` — zero config changes.
- **The install is portable to bare metal.** Everything karma references at
  boot lives *on the disk*: the LUKS container by partlabel, root via LVM
  (`pool/root`), `/boot` ESP by partlabel — all `by-partlabel`/UUID/LVM, never
  a bus device node. The `/dev/vda` in disko is used only while partitioning.
  Moving the SSD from virtio (VM) to nvme (metal) changes nothing it depends
  on. (Avoid `by-id` references — those *are* bus-coupled and would change on
  the move. karma has none.)
- **It boots on any UEFI firmware.** karma uses systemd-boot with
  `efi.canTouchEfiVariables = false`, so it installs the firmware-agnostic ESP
  fallback (`EFI/BOOT/BOOTX64.EFI`) and relies on it instead of a VM-local
  NVRAM entry. (karma is **UEFI-only** — boot the VM with OVMF, not SeaBIOS.)

## Prerequisites

- The repo's devenv shell active (`direnv allow` at the repo root) — provides
  `nixos-anywhere`, `sops`, `ssh-to-age`, and `SOPS_AGE_KEY_FILE`.
- YubiKey plugged in (needed to decrypt karma's host key from sops).
- virt-manager, working under the **QEMU/KVM system connection**
  (`qemu:///system`) — the system session is what lets the VM open the raw
  block device.
- A NixOS **minimal x86_64 ISO** downloaded locally.
- The target SSD identified and **idle/unmounted** on the host.

> Throughout, substitute your real device path for `/dev/nvme0n1` and the VM's
> real address for `192.168.122.100`.

## Phase 0 — Prep on the admin machine

**0.1 Identify and free the SSD.** ⚠️ The install **wipes this disk entirely**.

```sh
lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINTS   # confirm the target /dev/nvmeXn1
# unmount partitions; if it's in a host VG: vgchange -an <vg>; swapoff if swap
```

**0.2 Stage karma's existing host key.** karma is an existing host;
`secrets/karma.yaml` is encrypted to a `&karma` recipient derived from a
specific SSH host key. The installed system must carry that *same* key or
sops-nix can't decrypt on first boot (`tailscale`/`njalla-ddns` break). The key
is backed up inside the sops file — extract it into a staging tree that mirrors
the target's `/` (touch the YubiKey + enter PIN when prompted):

```sh
staging=$(mktemp -d) && mkdir -p "$staging/etc/ssh"
sops -d --extract '["ssh_host_ed25519_key"]' secrets/karma.yaml \
  > "$staging/etc/ssh/ssh_host_ed25519_key"
chmod 600 "$staging/etc/ssh/ssh_host_ed25519_key"
ssh-keygen -y -f "$staging/etc/ssh/ssh_host_ed25519_key" \
  > "$staging/etc/ssh/ssh_host_ed25519_key.pub"   # regenerate pubkey + validate
```

`$staging` is a plain shell variable holding a `mktemp` path — it only lives in
**this terminal session**. Keep it open through Phase 5 (cleanup), or note the
path now: `echo "$staging"`.

> **Forks:**
> - No `ssh_host_ed25519_key` entry in the sops file? Copy it off the live box
>   instead: `ssh root@karma cat /etc/ssh/ssh_host_ed25519_key > "$staging/etc/ssh/ssh_host_ed25519_key"`.
> - Want a *fresh* identity? Run `scripts/stage-host-keys.sh karma` and follow
>   its printed steps (edit `.sops.yaml`, `sops updatekeys`).
> - Throwaway disk/boot test where secrets don't matter? Skip 0.2 entirely and
>   drop `--extra-files` in Phase 3.

## Phase 1 — Create the VM in virt-manager

Work under the **QEMU/KVM system connection** (`qemu:///system`).

1. **New VM** → *Local install media* → select the NixOS minimal ISO. ~8 GB
   RAM, 4 vCPUs. On the final page tick **"Customize configuration before
   install"** → Finish.
2. **Firmware** (customize → Overview):
   - **Chipset:** Q35
   - **Firmware:** a **UEFI** option, e.g. `OVMF_CODE_4M.fd` (x86_64). Must be
     set now. Use the **plain** variant, *not* `*.secboot.fd` — karma's
     bootloader is unsigned and would fail under enrolled Secure Boot.
     virt-manager pairs it
     with the matching writable `OVMF_VARS_4M.fd` automatically.
3. **Add the SSD as a raw block disk** (*Add Hardware → Storage*):
   - Select **"Select or create custom storage"**, type the path
     **`/dev/nvme0n1`**.
   - **Device type:** `Disk device`
   - **Bus type:** **VirtIO**  ← gives `/dev/vda` in the guest
   - **Advanced options:** Cache mode `none`, Discard mode `unmap` (forwards
     TRIM; karma's LUKS has `allowDiscards`).
4. **Verify the disk XML** (enable XML editing in Preferences if needed):

   ```xml
   <disk type='block' device='disk'>
     <driver name='qemu' type='raw' cache='none' discard='unmap'/>
     <source dev='/dev/nvme0n1'/>
     <target dev='vda' bus='virtio'/>
   </disk>
   ```

   `type='block'` + `<source dev=…>` confirms true passthrough, not an image.
5. **Boot Options:** put the **CDROM (ISO) first**. Leave networking on the
   default NAT. **Begin Installation.**

## Phase 2 — Prep the live installer (VM console)

The ISO autologs in as `nixos`. Set a root password and find the VM IP:

```sh
sudo passwd root
lsblk          # sanity-check: the SSD must appear as  vda  (not sda)
ip -4 addr     # note the 192.168.122.x address
```

> If root SSH login is later refused, drop your pubkey in instead:
> `sudo mkdir -p /root/.ssh && sudo tee /root/.ssh/authorized_keys` (paste key).

## Phase 3 — Install with nixos-anywhere

From the repo root on the admin machine (x86_64 → builds locally, no flake copy
needed):

```sh
nixos-anywhere --extra-files "$staging" --flake .#karma root@192.168.122.100
```

`--extra-files "$staging"` overlays the staged tree onto the target's `/`, so
the staged host key lands at `/etc/ssh/ssh_host_ed25519_key` **before** the
first sops-nix activation.

During the run:
- Accept the host fingerprint → yes.
- Enter the VM **root password** you set in Phase 2 when SSH asks.
- It kexecs the VM into the installer; the SSH connection drops and reconnects
  — normal.
- disko wipes `vda` (your SSD) and **prompts you to set the LUKS passphrase** —
  choose one you'll remember; you'll type it at every real-hardware boot.

## Phase 4 — Verify, then relocate

**4.1 (Recommended) Test-boot inside the VM** before committing to hardware:

- Power off. Remove the CDROM (or set Boot Options → disk first). Boot.
- systemd-boot's removable ESP fallback makes OVMF boot it. Enter the
  LUKS passphrase → confirm you reach a karma login. This validates
  bootloader + LUKS + initrd on the same OVMF firmware before the move.

**4.2 Shred the staged key** (it holds a plaintext private key):

```sh
shred -u "$staging/etc/ssh/ssh_host_ed25519_key"
rm -rf "$staging"
```

If `$staging` is no longer set (new terminal), find it:
`ls -d /tmp/tmp.*/etc/ssh 2>/dev/null`, confirm it's yours, then shred/rm.

**4.3 Move the SSD** into the real machine and boot. Boot-time references are
all on-disk, so the virtio→nvme bus change is transparent — enter the LUKS
passphrase and it comes up.

## Phase 5 — (Optional) Add the YubiKey to LUKS, on real hardware

LUKS2 has multiple key slots, so you can add a YubiKey as a second slot while
keeping the passphrase as fallback (either one unlocks). FIDO2 enrollment needs
the physical key present, so do it on the real machine — not in the VM.

1. Set `boot.initrd.systemd.enable = true;` in karma's config (FIDO2 unlock
   needs the systemd initrd) and `nixos-rebuild switch`.
2. Enroll a second keyslot:

   ```sh
   sudo systemd-cryptenroll --fido2-device=auto /dev/disk/by-partlabel/disk-disk1-root
   ```

The keyslot is stored in the LUKS2 header on the SSD, independent of the
YubiKey's existing sops/PIV (age) role — same key, different applet, no
conflict. Keep at least the passphrase slot as recovery.
