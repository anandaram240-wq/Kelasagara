# KELASAGARA V20.15: CLOUD KMS KEYRINGS & HSM CRYPTO KEYS
# Segregates symmetric AES-256-GCM envelope encryption from asymmetric ECDSA P-256 signing keys.

resource "google_kms_key_ring" "biometrics" {
  name     = "biometric-identity-keyring-${var.environment}"
  location = var.region
  project  = var.sandbox_project_id

  lifecycle {
    prevent_destroy = true
  }
}

# 1. Biometric DEK Wrap Key (Symmetric AES-256-GCM)
# Hardware Security Module (FIPS 140-2 Level 3)
resource "google_kms_crypto_key" "dek_wrap" {
  name            = "biometric-dek-wrap-key"
  key_ring        = google_kms_key_ring.biometrics.id
  rotation_period = "7776000s" # 90-day automatic rotation
  purpose         = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }

  labels = var.required_labels

  lifecycle {
    prevent_destroy = true
  }
}

# 2. Manifest Attestation Key (Asymmetric ECDSA P-256)
# Used exclusively by the Release Architect to sign approved preprocessing manifests
resource "google_kms_crypto_key" "manifest_attestation" {
  name     = "manifest-attestation-key"
  key_ring = google_kms_key_ring.biometrics.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm        = "EC_SIGN_P256_SHA256"
    protection_level = "HSM"
  }

  labels = var.required_labels

  lifecycle {
    prevent_destroy = true
  }
}

# 3. Audit Checkpoint Signing Key (Asymmetric ECDSA P-256)
# Used exclusively by sa-biometrics-audit-notary to anchor external audit ledger checkpoints
resource "google_kms_crypto_key" "audit_checkpoint" {
  name     = "audit-checkpoint-signing-key"
  key_ring = google_kms_key_ring.biometrics.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm        = "EC_SIGN_P256_SHA256"
    protection_level = "HSM"
  }

  labels = var.required_labels

  lifecycle {
    prevent_destroy = true
  }
}
