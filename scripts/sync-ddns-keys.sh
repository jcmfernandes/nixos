#!/usr/bin/env bash
# Copy the Njalla DDNS keys from tofu state into each host's
# njalla_ddns_env sops secret. A record named <host>.<suffix> becomes
# DDNS_KEY_<SUFFIX> in <host>'s file (moon.internal → DDNS_KEY_INTERNAL);
# plain <host> becomes DDNS_KEY.
#
# Usage:  scripts/sync-ddns-keys.sh
# Notes:
#   - Run from the opentofu/ direnv shell: tofu output needs its state
#     credentials and encryption passphrase.
#   - Overwrites njalla_ddns_env whole; a file already holding the same
#     value is left untouched.

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)

for cmd in tofu jq sops; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: '$cmd' not on PATH; run from the opentofu devenv shell" >&2
    exit 1
  fi
done

keys=$(tofu -chdir="$repo_root/opentofu/infra" output -json ddns_keys)

for host in $(printf '%s' "$keys" | jq -r 'keys[] | split(".")[0]' | sort -u); do
  printf '%s' "$keys" \
    | jq -r --arg host "$host" '
        to_entries[]
        | select(.key | split(".")[0] == $host)
        | (["DDNS_KEY"] + (.key | split(".")[1:] | map(ascii_upcase)))
          as $name
        | "\($name | join("_"))=\(.value)"
      ' \
    | jq -Rs . \
    | sops set --idempotent --value-stdin \
      "$repo_root/secrets/$host.yaml" '["njalla_ddns_env"]'
  echo "secrets/$host.yaml: njalla_ddns_env synced" >&2
done
