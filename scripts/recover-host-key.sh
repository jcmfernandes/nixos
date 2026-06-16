#!/usr/bin/env bash
# Recover an existing host's SSH host key from secrets/<host>.yaml into a
# staging tree laid out for `nixos-anywhere --extra-files`. Complements
# scripts/stage-host-keys.sh (which *generates* a fresh identity); this one
# *recovers* the identity already backed up in sops, so a reinstall keeps the
# same age recipient and secrets keep decrypting on first boot.
#
# Usage:  staging=$(scripts/recover-host-key.sh <host>)
#   - The staging directory path is printed on stdout (capture it into
#     $staging); all diagnostics go to stderr.
#   - Decrypting the key needs the YubiKey (PIN + touch) or the backup age key.
#   - The staging tree holds a PLAINTEXT private key under $TMPDIR. Shred it
#     after nixos-anywhere has run successfully:
#       shred -u "$staging/etc/ssh/ssh_host_ed25519_key" && rm -rf "$staging"

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <host>" >&2
  exit 1
fi

host=$1
repo_root=$(cd "$(dirname "$0")/.." && pwd)
host_secrets="$repo_root/secrets/${host}.yaml"

for cmd in sops ssh-keygen; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: '$cmd' not on PATH; run from the devenv shell" >&2
    exit 1
  fi
done

if [ ! -f "$host_secrets" ]; then
  echo "error: $host_secrets not found" >&2
  exit 1
fi

# Field names stay plaintext in a sops file, so we can fail early (before
# touching the YubiKey) with a clear message if the key isn't backed up here.
if ! grep -q '^ssh_host_ed25519_key:' "$host_secrets"; then
  echo "error: no ssh_host_ed25519_key entry in $host_secrets" >&2
  echo "       generate one with scripts/stage-host-keys.sh, or copy it off" >&2
  echo "       the live host:  ssh root@${host} cat /etc/ssh/ssh_host_ed25519_key" >&2
  exit 1
fi

staging=$(mktemp -d -t "recover-${host}-XXXXXX")
chmod 700 "$staging"
mkdir -p "$staging/etc/ssh"
key="$staging/etc/ssh/ssh_host_ed25519_key"

# Decrypt just the host key (YubiKey PIN + touch) straight into the staging
# tree — plaintext only ever lands in this one file.
if ! sops -d --extract '["ssh_host_ed25519_key"]' "$host_secrets" > "$key"; then
  echo "error: failed to decrypt ssh_host_ed25519_key from $host_secrets" >&2
  rm -rf "$staging"
  exit 1
fi
chmod 600 "$key"

# Regenerate the public half from the private key; this also validates that the
# extracted key is well-formed (a truncated/garbled key makes ssh-keygen fail).
if ! ssh-keygen -y -f "$key" > "$key.pub" 2>/dev/null; then
  echo "error: recovered key is not a valid OpenSSH private key" >&2
  rm -rf "$staging"
  exit 1
fi

{
  echo "recovered ${host} host key into staging tree:"
  echo "  $key      (0600)"
  echo "  $key.pub"
  echo
  echo "install:  nixos-anywhere --extra-files \"\$staging\" --flake .#${host} root@<vm-ip>"
  echo "cleanup:  shred -u \"$key\" && rm -rf \"$staging\""
} >&2

# stdout = the staging path only, so callers can do:  staging=$(... )
echo "$staging"
