# IONOS S3 buckets managed via the native IONOS provider.
#
# `home-infra-backups` predates terraform; bring it under management with:
#   tofu import ionoscloud_s3_bucket.backups home-infra-backups
# Do that before the next `tofu apply` so apply doesn't try to recreate it.

resource "ionoscloud_s3_bucket" "backups" {
  name   = var.backups_bucket_name
  region = var.ionos_s3_region

  # Holds restic backups; refuse to delete it even under `tofu destroy`.
  # To intentionally drop the bucket, remove this block first.
  lifecycle {
    prevent_destroy = true
  }
}

resource "ionoscloud_s3_bucket" "nix_cache" {
  name   = var.nix_cache_bucket_name
  region = var.ionos_s3_region
}

resource "ionoscloud_s3_bucket" "opentofu_state" {
  name   = var.opentofu_state_bucket_name
  region = var.ionos_s3_region

  # Holds the remote OpenTofu state for this config; losing it = losing
  # track of every managed resource. To intentionally drop the bucket,
  # remove this block first.
  lifecycle {
    prevent_destroy = true
  }
}

# Dedicated S3 access key for the Attic service on vivivi. Scoped to one
# service so it can be rotated independently of the keys restic uses.
resource "ionoscloud_s3_key" "attic" {
  user_id = var.ionos_user_id
  active  = true
}
