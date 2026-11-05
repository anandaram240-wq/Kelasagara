# KELASAGARA V20.15: CLOUD STORAGE AUDIT CHECKPOINT BUCKET
# Configures immutable audit bucket with UNLOCKED retention (is_locked = false) and enforced public access block.

resource "google_storage_bucket" "audit_checkpoints" {
  name          = "${var.sandbox_project_id}-biometric-audit-checkpoints"
  location      = var.region
  project       = var.sandbox_project_id
  force_destroy = false

  # Mandatory uniform bucket-level access
  uniform_bucket_level_access = true

  # Mandatory public access prevention
  public_access_prevention = "enforced"

  # Versioning ensures previous versions are retained
  versioning {
    enabled = true
  }

  # Retention policy: UNLOCKED in Phase 20.15 to prevent accidental irreversible lock
  retention_policy {
    is_locked        = false # Must remain false in non-production sandbox
    retention_period = var.audit_retention_days * 86400
  }

  labels = var.required_labels

  lifecycle {
    prevent_destroy = true
  }
}
