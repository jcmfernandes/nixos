variable "tenancy_ocid" {
  type        = string
  description = "OCI tenancy OCID."
}

variable "user_ocid" {
  type        = string
  description = "OCI user OCID."
}

variable "compartment_ocid" {
  type        = string
  description = "Compartment to create resources in. Use the tenancy OCID for the root compartment."
}

variable "region" {
  type        = string
  description = "OCI region (e.g. eu-madrid-1)."
}

variable "fingerprint" {
  type        = string
  description = "API key fingerprint shown by OCI Console after uploading the public key."
}

variable "instance_name" {
  type        = string
  description = "VM display name."
  default     = "vivivi"
}

variable "ocpus" {
  type        = number
  description = "OCPUs for VM.Standard.A1.Flex. Free tier cap is 4 across all A1 instances."
  default     = 4
}

variable "memory_in_gbs" {
  type        = number
  description = "RAM in GB. Free tier cap is 24 across all A1 instances."
  default     = 24
}

variable "boot_volume_size_in_gbs" {
  type        = number
  description = "Boot volume size in GB. Free tier block storage cap is 200 total."
  default     = 200
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "CIDR allowed to reach port 22. 0.0.0.0/0 = open to the world (key-only auth)."
  default     = "0.0.0.0/0"
}

variable "ssh_keys_url" {
  type        = string
  description = "URL returning newline-separated SSH public keys (e.g. https://github.com/<user>.keys)."
  default     = "https://github.com/jcmfernandes.keys"
}

variable "ionos_s3_region" {
  type        = string
  description = "IONOS S3 region (e.g. eu-central-3, de)."
  default     = "eu-central-3"
}

variable "ionos_user_id" {
  type        = string
  description = "IONOS user UUID that the per-service S3 keys belong to. DCD -> Management -> User Management -> your user."
}

variable "nix_cache_bucket_name" {
  type        = string
  description = "Bucket for the Attic nix binary cache."
  default     = "moreirafernandesdotcom-nix-cache"
}

variable "backups_bucket_name" {
  type        = string
  description = "Bucket holding restic backups (immich + state)."
  default     = "home-infra-backups"
}

variable "opentofu_state_bucket_name" {
  type        = string
  description = "Bucket holding the remote OpenTofu state for this config."
  default     = "moreirafernandesdotcom-opentofu-state"
}

# --- DNS (Njalla) ----------------------------------------------------------

variable "apex_domain" {
  type        = string
  description = "Apex domain managed at Njalla."
  default     = "moreirafernandes.com"
}

variable "dns_ttl" {
  type        = number
  description = "TTL for the service CNAME records. Must be one of gonjalla's ValidTTL values."
  default     = 60
}
