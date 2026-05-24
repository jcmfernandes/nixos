terraform {
  required_version = ">= 1.7.0"

  # State and plan files are encrypted at rest with AES-GCM keyed off a
  # passphrase derived via PBKDF2. OpenTofu's encryption block can't take
  # dynamic values, so the passphrase is merged in via the TF_ENCRYPTION
  # env var (populated by opentofu/.envrc from secrets/infra.yaml).
  encryption {
    key_provider "pbkdf2" "passphrase" {}

    method "aes_gcm" "default" {
      keys = key_provider.pbkdf2.passphrase
    }

    state {
      method = method.aes_gcm.default
    }

    plan {
      method = method.aes_gcm.default
    }
  }

  # Remote state lives in the IONOS S3 bucket created by storage.tf. Backend
  # blocks can't reference variables, so credentials must be supplied at init
  # time via AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars (the s3
  # backend uses the same env var names regardless of provider) holding the
  # IONOS S3 key.
  backend "s3" {
    bucket = "moreirafernandesdotcom-opentofu-state"
    key    = "infra.tfstate"
    region = "eu-central-3"
    endpoints = {
      s3 = "https://s3.eu-central-3.ionoscloud.com"
    }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.0"
    }
    ionoscloud = {
      source  = "ionos-cloud/ionoscloud"
      version = "~> 6.7"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
    njalla = {
      source  = "Sighery/njalla"
      version = "~> 0.5"
    }
  }
}
