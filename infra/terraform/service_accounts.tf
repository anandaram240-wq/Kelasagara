# KELASAGARA V20.14: DEDICATED SERVICE ACCOUNT IDENTITIES
# Declares discrete, task-specific service principals adhering to NIST SP 800-207 Zero Trust

# 1. Biometric Enrollment Identity
resource "google_service_account" "enrollment" {
  account_id   = "sa-biometrics-enrollment"
  display_name = "Kelasagara Biometric Enrollment Service"
  description  = "Dedicated principal for ingesting canonical face templates, wrapping DEKs, and writing pending records. Prohibited from unwrapping DEKs or modifying active templates."
  project      = var.sandbox_project_id
}

# 2. Biometric Verifier & Deduplication Identity
resource "google_service_account" "verifier" {
  account_id   = "sa-biometrics-verifier"
  display_name = "Kelasagara Biometric Verifier & Deduplication Service"
  description  = "Dedicated principal for running 1:N deduplication queries and unwrapping DEKs under approved verification contexts. Prohibited from creating or replacing biometric templates."
  project      = var.sandbox_project_id
}

# 3. Adjudication & Case Reviewer Identity
resource "google_service_account" "reviewer" {
  account_id   = "sa-biometrics-reviewer"
  display_name = "Kelasagara Biometric Duplicate Case Reviewer Service"
  description  = "Dedicated principal for resolving blinded duplicate cases. Prohibited from accessing raw face embeddings or Cloud KMS decryption keys."
  project      = var.sandbox_project_id
}

# 4. Inventory & Metadata Scanner Identity
resource "google_service_account" "inventory" {
  account_id   = "sa-biometrics-inventory"
  display_name = "Kelasagara Biometric Vault Metadata Scanner"
  description  = "Dedicated strictly read-only principal for counting template classifications and audit status. Zero write, update, or delete capability."
  project      = var.sandbox_project_id
}

# 5. Audit Notary & Checkpoint Identity
resource "google_service_account" "audit_notary" {
  account_id   = "sa-biometrics-audit-notary"
  display_name = "Kelasagara Biometric Audit Notary & Ledger Anchor"
  description  = "Dedicated principal for appending sequenced audit events and uploading signed ECDSA checkpoints to immutable Cloud Storage. Prohibited from modifying templates."
  project      = var.sandbox_project_id
}
