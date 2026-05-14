# Secrets decrypted at plan/apply time from secrets.sops.yaml. Requires
# SOPS_AGE_KEY_FILE pointing at an age identity that can decrypt the file
# (the project's .envrc already sets this).
data "sops_file" "secrets" {
  source_file = "../../secrets/infra.yaml"
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = data.sops_file.secrets.data["oci_api_key"]
  region       = var.region
}

# IONOS provider. `token` is the Cloud API JWT (used for non-S3 resources
# like ionoscloud_s3_key); `s3_access_key`/`s3_secret_key` are the bucket-
# level S3 credentials used for ionoscloud_s3_bucket operations.
provider "ionoscloud" {
  token         = data.sops_file.secrets.data["ionos_token"]
  s3_access_key = data.sops_file.secrets.data["ionos_s3_access_key"]
  s3_secret_key = data.sops_file.secrets.data["ionos_s3_secret_key"]
}
