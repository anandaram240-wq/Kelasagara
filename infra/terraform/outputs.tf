# KELASAGARA V20.15: SAFE NON-SENSITIVE TERRAFORM OUTPUTS
# Exposes non-sensitive resource identifiers for application service discovery

output "environment" {
  description = "Configured non-production deployment environment."
  value       = var.environment
}

output "project_id" {
  description = "Configured sandbox Google Cloud project ID."
  value       = var.sandbox_project_id
}

output "service_accounts" {
  description = "Emails of the dedicated service account identities."
  value = {
    enrollment   = google_service_account.enrollment.email
    verifier     = google_service_account.verifier.email
    reviewer     = google_service_account.reviewer.email
    inventory    = google_service_account.inventory.email
    audit_notary = google_service_account.audit_notary.email
  }
}

output "kms_key_ring_id" {
  description = "Regional Cloud KMS Keyring identifier."
  value       = google_kms_key_ring.biometrics.id
}

output "audit_storage_bucket_name" {
  description = "Name of the immutable Cloud Storage audit checkpoint bucket."
  value       = google_storage_bucket.audit_checkpoints.name
}

output "firestore_databases" {
  description = "Names of the isolated named Firestore databases."
  value = {
    biometric_vault = google_firestore_database.biometric_vault.name
    audit_ledger    = google_firestore_database.audit_ledger.name
  }
}
