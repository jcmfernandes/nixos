#!/usr/bin/env bash
# Generate an OpenSSH ed25519 host key for <host> on this admin machine,
# derive the matching age recipient, stash the private key inside the
# host's sops file (admin-recoverable identity backup), and stage the
# keypair for upload via `nixos-anywhere --extra-files`. After install,
# the host's age identity matches the recipient already listed in
# .sops.yaml, so sops-nix can decrypt secrets on first boot.
#
# Usage:  scripts/stage-host-keys.sh <host>
# Notes:
#   - The private key briefly lives at $staging/etc/ssh/ssh_host_ed25519_key
#     (mode 600). Shred it after nixos-anywhere has run successfully.
#   - Refuses to clobber an existing ssh_host_ed25519_key entry in
#     secrets/<host>.yaml — remove it first if you really mean to rotate.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <host>" >&2
  exit 1
fi

host=$1
repo_root=$(cd "$(dirname "$0")/.." && pwd)
sops_yaml="$repo_root/.sops.yaml"
host_secrets="$repo_root/secrets/${host}.yaml"

for cmd in ssh-keygen ssh-to-age sops; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: '$cmd' not on PATH; run from the devenv shell" >&2
    exit 1
  fi
done

if [ ! -f "$sops_yaml" ]; then
  echo "error: $sops_yaml not found" >&2
  exit 1
fi

staging=$(mktemp -d -t "stage-${host}-XXXXXX")
chmod 700 "$staging"
mkdir -p "$staging/etc/ssh"

ssh-keygen -q -t ed25519 -N '' -C "root@${host}" \
  -f "$staging/etc/ssh/ssh_host_ed25519_key"

key_path="$staging/etc/ssh/ssh_host_ed25519_key"
recipient=$(ssh-to-age < "${key_path}.pub")

# Embed the private key into secrets/<host>.yaml so an admin (yubikey +
# backup) can recover the host's identity if the box ever needs a
# reinstall. Plaintext only ever lives in the pipe between sops processes
# — never written to disk by this script.
if [ -f "$host_secrets" ]; then
  if grep -q '^sops:' "$host_secrets"; then
    emit_existing() { sops --decrypt "$host_secrets"; }
  else
    emit_existing() { cat "$host_secrets"; }
  fi
  if emit_existing | grep -q '^ssh_host_ed25519_key:'; then
    echo "error: ssh_host_ed25519_key already present in $host_secrets" >&2
    echo "       remove it first if you intend to rotate the host identity" >&2
    rm -rf "$staging"
    exit 1
  fi
  { emit_existing; \
    printf '\nssh_host_ed25519_key: |\n'; \
    sed 's/^/  /' "$key_path"; } \
    | sops --encrypt --input-type yaml --output-type yaml \
        --filename-override "$host_secrets" /dev/stdin \
    > "${host_secrets}.new"
  mv "${host_secrets}.new" "$host_secrets"
else
  # No existing file — create one with just the host key. .sops.yaml must
  # already have a creation_rule for secrets/<host>.yaml or sops will
  # refuse.
  { printf 'ssh_host_ed25519_key: |\n'; \
    sed 's/^/  /' "$key_path"; } \
    | sops --encrypt --input-type yaml --output-type yaml \
        --filename-override "$host_secrets" /dev/stdin \
    > "$host_secrets"
fi

cat <<EOF
Staged host key for '$host':
  $staging/etc/ssh/ssh_host_ed25519_key       (private, 0600)
  $staging/etc/ssh/ssh_host_ed25519_key.pub   (public)
Backed up into:
  $host_secrets  (as ssh_host_ed25519_key)

Age recipient:
  - &${host}  ${recipient}

Next steps (run from the repo root):

  1. Add the recipient line to .sops.yaml under \`keys:\` and reference
     it via \`*${host}\` in the secrets/${host}.yaml creation_rule.

  2. Re-encrypt secrets/${host}.yaml so the host itself becomes a
     recipient (alongside yubikey + backup):
       sops updatekeys secrets/${host}.yaml

  3. Install with nixos-anywhere, pointing it at the staging dir so the
     host key lands at /etc/ssh/ssh_host_ed25519_key before sops-nix
     activation:
       nixos-anywhere --extra-files $staging --flake .#${host} root@<install-target>

  4. After install confirms first-boot decryption works:
       shred -u $staging/etc/ssh/ssh_host_ed25519_key
       rm -rf $staging

  Recovery: if ${host} ever needs reinstalling, decrypt secrets/${host}.yaml,
  extract ssh_host_ed25519_key into a fresh staging dir laid out as
  etc/ssh/ssh_host_ed25519_key, and re-run nixos-anywhere with the same
  --extra-files — identity is preserved, secrets keep decrypting.
EOF
