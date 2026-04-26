# moon — backup restore

Two nightly restic jobs push to IONOS S3. This file documents how to bring data back.

## Two repos, one bucket

| Repo | Unit | What it holds | Retention | Schedule |
|---|---|---|---|---|
| `immich` | `restic-backups-immich.service` | `/data/photos`, Immich Postgres dump | 14d / 8w / 24m | 03:30 daily |
| `state` | `restic-backups-state.service` | `/data/state/nixarr`, SQLite snapshots of sonarr/radarr/prowlarr/bazarr, Tailscale state | 7d / 4w | 04:30 daily |

Both repos live in the same IONOS bucket at different prefixes; both use the same S3 credentials. Encryption passwords are separate.

## What's in each backup

### `immich` repo

| Path on moon | Purpose |
|---|---|
| `/data/photos` | Immich media (originals + albums, excluding derivable subdirs) |
| `/var/backup/immich-db.sql.gz` | Postgres dump of the `immich` database (written by `backupPrepareCommand`) |

Excluded (regenerated on first post-restore run): `/data/photos/thumbs`, `/data/photos/encoded-video`.

### `state` repo

| Path on moon | Purpose |
|---|---|
| `/data/state/nixarr` | Sonarr/Radarr/Prowlarr/Bazarr/Plex/Transmission state |
| `/var/backup/{sonarr,radarr,prowlarr,bazarr}.db` | Consistent SQLite snapshots via `sqlite3 .backup` |
| `/var/lib/tailscale/tailscaled.state` | Tailscale node identity |

Excluded (regenerated): `Plex Media Server/{Cache,Logs,Crash Reports}`.

Excluded because the dumps are authoritative: the live `*.db{,-shm,-wal}` SQLite files under each arr's state dir.

## What's NOT in either backup (needed to access them)

These must be reprovisioned out-of-band before a restore is possible:

- `/var/lib/luks-keys/data.key` — to unlock the btrfs-on-LUKS data disks.
- `/var/lib/restic/immich.repo`, `/var/lib/restic/immich.password`
- `/var/lib/restic/state.repo`, `/var/lib/restic/state.password`
- `/var/lib/restic/ionos.env` — shared IONOS S3 credentials.
- `/var/lib/njalla/{ddns,caddy}.env` — regenerable in the Njalla panel.
- `/var/lib/ntfy/url` — regenerable.

**Keep `data.key` and both restic passwords somewhere off moon.** Losing any restic password makes its repo permanently unrecoverable.

## Prerequisites for a restore

1. moon (or replacement Pi) booted with this flake applied — `nixos-rebuild switch --flake .#moon --target-host root@moon`.
2. The five files listed above in place at their expected paths.
3. `/var/lib/luks-keys/data.key` in place **if** the data disks are already LUKS-formatted with that key (see "Full disaster recovery" if disks are also gone).

### Helper: exporting env for ad-hoc restic commands

Every `restic` command below assumes you've picked a repo and exported its env. Example for the `immich` repo:

```sh
set -a; . /var/lib/restic/ionos.env; set +a
export RESTIC_REPOSITORY_FILE=/var/lib/restic/immich.repo
export RESTIC_PASSWORD_FILE=/var/lib/restic/immich.password
```

Swap `immich.{repo,password}` → `state.{repo,password}` to operate on the other repo. Sanity-check with `restic snapshots` before touching anything.

## Full disaster recovery (moon + disks gone)

1. **Reinstall NixOS** on a fresh Pi 5 SD card with this flake. Services depending on `/data` will fail until disks are unlocked and mounted.

2. **Format and LUKS-encrypt the replacement disks** with the restored key:
   ```sh
   install -d -m 700 -o root -g root /var/lib/luks-keys
   # paste the backed-up key file into /var/lib/luks-keys/data.key
   chmod 400 /var/lib/luks-keys/data.key

   for dev in /dev/disk/by-id/ata-...-part1; do
     cryptsetup luksFormat --type luks2 --batch-mode --key-file /var/lib/luks-keys/data.key "$dev"
   done
   ```

3. **Open LUKS, create btrfs, let systemd mount** (or `mount -a` after updating device names in `configuration.nix`). See the main configuration for the expected serial-to-mapper mapping.

4. **Drop all restic secrets** (see Prerequisites).

5. **Restore the `immich` repo first** (photos + Postgres dump):
   ```sh
   set -a; . /var/lib/restic/ionos.env; set +a
   export RESTIC_REPOSITORY_FILE=/var/lib/restic/immich.repo
   export RESTIC_PASSWORD_FILE=/var/lib/restic/immich.password
   restic restore latest --target /
   ```

6. **Restore the `state` repo** (arr state + DB snapshots + Tailscale state):
   ```sh
   export RESTIC_REPOSITORY_FILE=/var/lib/restic/state.repo
   export RESTIC_PASSWORD_FILE=/var/lib/restic/state.password
   restic restore latest --target /
   ```

7. **Restore the Immich Postgres database** from the dump that was just restored:
   ```sh
   systemctl stop immich-server
   systemctl start postgresql
   runuser -u immich -- dropdb --if-exists immich
   runuser -u immich -- createdb immich
   gunzip -c /var/backup/immich-db.sql.gz | runuser -u immich -- psql immich
   systemctl start immich-server
   ```

8. **Swap in the arr SQLite snapshots** in place of the excluded live DBs:
   ```sh
   systemctl stop sonarr radarr prowlarr bazarr
   cp /var/backup/sonarr.db   /data/state/nixarr/sonarr/sonarr.db
   cp /var/backup/radarr.db   /data/state/nixarr/radarr/radarr.db
   cp /var/backup/prowlarr.db /data/state/nixarr/prowlarr/prowlarr.db
   cp /var/backup/bazarr.db   /data/state/nixarr/bazarr/db/bazarr.db
   chown sonarr:media    /data/state/nixarr/sonarr/sonarr.db
   chown radarr:media    /data/state/nixarr/radarr/radarr.db
   chown prowlarr:root   /data/state/nixarr/prowlarr/prowlarr.db
   chown bazarr:root     /data/state/nixarr/bazarr/db/bazarr.db
   systemctl start sonarr radarr prowlarr bazarr
   ```

9. **Restore Tailscale state**:
   ```sh
   systemctl stop tailscaled
   chown root:root /var/lib/tailscale/tailscaled.state
   chmod 600 /var/lib/tailscale/tailscaled.state
   systemctl start tailscaled
   ```
   moon rejoins the tailnet with its original `100.x.y.z` IP, no admin-console action needed.

10. **Verify**:
    ```sh
    systemctl status immich-server sonarr radarr prowlarr bazarr transmission plex tailscaled
    ```

## Partial recovery scenarios

Remember to export the right repo's env first.

### Restore a single file (immich repo)

```sh
export RESTIC_REPOSITORY_FILE=/var/lib/restic/immich.repo
export RESTIC_PASSWORD_FILE=/var/lib/restic/immich.password
restic restore latest --include /data/photos/library/admin/2025/something.jpg --target /tmp/recovered
```

### Restore only the Immich database

```sh
systemctl stop immich-server

export RESTIC_REPOSITORY_FILE=/var/lib/restic/immich.repo
export RESTIC_PASSWORD_FILE=/var/lib/restic/immich.password
restic restore latest --include /var/backup/immich-db.sql.gz --target /tmp/dbrestore
gunzip -c /tmp/dbrestore/var/backup/immich-db.sql.gz \
  | runuser -u immich -- psql immich

systemctl start immich-server
```

### Restore only one arr's state (e.g. Sonarr)

The live `sonarr.db` is excluded; the consistent snapshot at `/var/backup/sonarr.db` is authoritative.

```sh
systemctl stop sonarr
mv /data/state/nixarr/sonarr /data/state/nixarr/sonarr.broken

export RESTIC_REPOSITORY_FILE=/var/lib/restic/state.repo
export RESTIC_PASSWORD_FILE=/var/lib/restic/state.password
restic restore latest \
  --include /data/state/nixarr/sonarr \
  --include /var/backup/sonarr.db \
  --target /

cp /var/backup/sonarr.db /data/state/nixarr/sonarr/sonarr.db
chown sonarr:media /data/state/nixarr/sonarr/sonarr.db

systemctl start sonarr
```

Same pattern for radarr/prowlarr/bazarr — adjust service name, DB path, and owner per the "Swap in" step above.

### Restore only Tailscale state

```sh
systemctl stop tailscaled
export RESTIC_REPOSITORY_FILE=/var/lib/restic/state.repo
export RESTIC_PASSWORD_FILE=/var/lib/restic/state.password
restic restore latest --include /var/lib/tailscale/tailscaled.state --target /
chown root:root /var/lib/tailscale/tailscaled.state
chmod 600 /var/lib/tailscale/tailscaled.state
systemctl start tailscaled
```

### Browse a repo interactively

```sh
# point at whichever repo
export RESTIC_REPOSITORY_FILE=/var/lib/restic/state.repo
export RESTIC_PASSWORD_FILE=/var/lib/restic/state.password
restic mount /mnt/restic
# snapshots appear under /mnt/restic/snapshots/<id>/
# read-only, cp freely, umount /mnt/restic when done
```

## Periodic restore drill (recommended)

Once a quarter, prove both repos restore cleanly:

```sh
dir=/tmp/drill-$(date +%F)
mkdir -p "$dir/immich" "$dir/state"

set -a; . /var/lib/restic/ionos.env; set +a

export RESTIC_REPOSITORY_FILE=/var/lib/restic/immich.repo
export RESTIC_PASSWORD_FILE=/var/lib/restic/immich.password
restic restore latest --target "$dir/immich"
gunzip -t "$dir/immich/var/backup/immich-db.sql.gz" && echo "immich db dump OK"

export RESTIC_REPOSITORY_FILE=/var/lib/restic/state.repo
export RESTIC_PASSWORD_FILE=/var/lib/restic/state.password
restic restore latest --target "$dir/state"
sqlite3 "$dir/state/var/backup/sonarr.db" ".tables" >/dev/null && echo "sonarr dump OK"

rm -rf "$dir"
```
