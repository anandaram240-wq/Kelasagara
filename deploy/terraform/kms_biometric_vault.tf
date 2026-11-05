# deploy/terraform/kms_biometric_vault.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
  }
}

variable "project_id" {
  type        = string
  description = "Target GCP project ID (staging guard blocks kelasagara-prod unless explicitly overridden by prod pipeline)."
  validation {
    condition     = var.project_id != "kelasagara-prod"
    error_message = "STAGING_GUARD_BLOCKED: Direct execution against kelasagara-prod is prohibited in staging verification."
  }
}

variable "region" {
  type        = string
  default     = "asia-south1"
  description = "GCP region supporting Cloud HSM (Mumbai: asia-south1)."
}

variable "cloud_run_service_account_email" {
  type        = string
  description = "Service account email for the Kelasagara biometric backend."
}

resource "google_kms_key_ring" "kelasagara_biometric_vault_ring" {
  name     = "kelasagara-biometric-vault-ring"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "biometric_template_dek_kek" {
  name            = "biometric-template-dek-kek"
  key_ring        = google_kms_key_ring.kelasagara_biometric_vault_ring.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s" # 90 days automatic rotation

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "biometric_backend_kek_binding" {
  crypto_key_id = google_kms_crypto_key.biometric_template_dek_kek.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${var.cloud_run_service_account_email}"
}

output "kms_key_ring_id" {
  value = google_kms_key_ring.kelasagara_biometric_vault_ring.id
}

output "kms_crypto_key_id" {
  value = google_kms_crypto_key.biometric_template_dek_kek.id
}
