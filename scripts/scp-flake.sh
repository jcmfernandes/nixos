#!/usr/bin/env bash
# Copy this flake to a target host (default: /etc/nixos) so the target
# can `nixos-rebuild switch --flake .#<host>` against a local copy
# instead of pulling over the network from the admin machine.
#
# Why not just `scp -r .` ? Because the working tree contains things
# you don't want on the host: .git/, .direnv/, opentofu/ state, plaintext
# `age-identities`, oci.pem, tfvars, etc. This script uses git to
# enumerate tracked + staged + dirty files (exactly what a `git+file:`
# flake would evaluate against) and streams that subset over ssh via
# tar, which is the scp-flavored "copy a curated tree" idiom in Nix-land.
#
# Usage:  scripts/scp-flake.sh <ssh-target> [remote-path]
# e.g.    scripts/scp-flake.sh root@vivivi
#         scripts/scp-flake.sh root@vivivi /tmp/flake-staging
#
# Notes:
#   - Encrypted secrets (secrets/*.yaml) ARE included; they're tracked
#     and the target needs them for sops-nix activation.
#   - The remote directory is wiped before extraction so deletions in
#     the source tree propagate.

set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: $0 <ssh-target> [remote-path]" >&2
  exit 1
fi

target=$1
remote_path=${2:-/etc/nixos}
repo_root=$(cd "$(dirname "$0")/.." && pwd)

if ! command -v git >/dev/null 2>&1; then
  echo "error: git required on local host" >&2
  exit 1
fi

if [ ! -d "$repo_root/.git" ]; then
  echo "error: $repo_root is not a git repo" >&2
  exit 1
fi

# `git stash create` captures both staged and unstaged working-tree
# changes into a throwaway commit object without disturbing the index.
# Falls back to HEAD when the tree is clean (`create` prints nothing
# in that case).
ref=$(git -C "$repo_root" stash create 2>/dev/null || true)
ref=${ref:-HEAD}

echo "Streaming tracked + dirty files from $repo_root → $target:$remote_path"

git -C "$repo_root" archive --format=tar "$ref" \
  | ssh "$target" "set -euo pipefail
      mkdir -p '$remote_path'
      # Wipe everything except dotfiles we don't manage. Then extract.
      find '$remote_path' -mindepth 1 -maxdepth 1 \
        ! -name '.git' ! -name '.direnv' \
        -exec rm -rf {} +
      tar -xf - -C '$remote_path'
      echo 'Synced. Top level:'
      ls -la '$remote_path' | head -15
    "
