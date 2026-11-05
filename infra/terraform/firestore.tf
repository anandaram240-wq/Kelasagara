# KELASAGARA V20.15: FIRESTORE NAMED DATABASES FOR ISOLATED TRUST DOMAINS
# Multi-database topography isolating sensitive biometric vault and audit trails from default app data

# 1. Biometric Vault Dedicated Database
resource "google_firestore_database" "biometric_vault" {
  project                 = var.sandbox_project_id
  name                    = "biometric-vault-db"
  location_id             = var.region
  type                    = "FIRESTORE_NATIVE"
  concurrency_mode        = "OPTIMISTIC"
  delete_protection_state = "DELETE_PROTECTION_ENABLED"

  lifecycle {
    prevent_destroy = true
  }
}

# 2. Audit Ledger Dedicated Database
resource "google_firestore_database" "audit_ledger" {
  project                 = var.sandbox_project_id
  name                    = "audit-ledger-db"
  location_id             = var.region
  type                    = "FIRESTORE_NATIVE"
  concurrency_mode        = "OPTIMISTIC"
  delete_protection_state = "DELETE_PROTECTION_ENABLED"

  lifecycle {
    prevent_destroy = true
  }
}
