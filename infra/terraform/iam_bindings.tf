# KELASAGARA V20.15: IAM BINDINGS WITH STRICT SIGNER/VERIFIER SEPARATION
# Corrects KMS roles by separating roles/cloudkms.signer from roles/cloudkms.verifier.

# ─── 1. Enrollment Service Account IAM Bindings ─────────────────────────────
# Can write pending templates to Datastore/Firestore
resource "google_project_iam_member" "enrollment_datastore" {
  project = var.sandbox_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.enrollment.email}"
}

# Can ONLY ENCRYPT (wrap DEK) with KMS; CANNOT DECRYPT
resource "google_kms_crypto_key_iam_member" "enrollment_kms_encrypter" {
  crypto_key_id = google_kms_crypto_key.dek_wrap.id
  role          = "roles/cloudkms.cryptoKeyEncrypter"
  member        = "serviceAccount:${google_service_account.enrollment.email}"
}

# ─── 2. Verifier Service Account IAM Bindings ───────────────────────────────
# Can ONLY READ active gallery index from Datastore/Firestore; CANNOT WRITE
resource "google_project_iam_member" "verifier_datastore" {
  project = var.sandbox_project_id
  role    = "roles/datastore.viewer"
  member  = "serviceAccount:${google_service_account.verifier.email}"
}

# Can ONLY DECRYPT (unwrap DEK) with KMS for 1:N deduplication; CANNOT ENCRYPT
resource "google_kms_crypto_key_iam_member" "verifier_kms_decrypter" {
  crypto_key_id = google_kms_crypto_key.dek_wrap.id
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  member        = "serviceAccount:${google_service_account.verifier.email}"
}

# Verifier can verify signatures on manifest attestation (VERIFIER ONLY, CANNOT SIGN)
resource "google_kms_crypto_key_iam_member" "verifier_manifest_key_verifier" {
  crypto_key_id = google_kms_crypto_key.manifest_attestation.id
  role          = "roles/cloudkms.verifier"
  member        = "serviceAccount:${google_service_account.verifier.email}"
}

# ─── 3. Reviewer Service Account IAM Bindings ───────────────────────────────
# Limited to case status updates; ZERO KMS ACCESS (cannot decrypt templates)
resource "google_project_iam_member" "reviewer_datastore" {
  project = var.sandbox_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.reviewer.email}"
}

# ─── 4. Inventory Metadata Scanner IAM Bindings ─────────────────────────────
# Strictly read-only metadata viewer; ZERO WRITE CAPABILITY, ZERO KMS ACCESS
resource "google_project_iam_member" "inventory_datastore" {
  project = var.sandbox_project_id
  role    = "roles/datastore.viewer"
  member  = "serviceAccount:${google_service_account.inventory.email}"
}

# ─── 5. Audit Notary Service Account IAM Bindings ───────────────────────────
# Can append audit events
resource "google_project_iam_member" "audit_notary_datastore" {
  project = var.sandbox_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.audit_notary.email}"
}

# Can upload signed checkpoints to Cloud Storage; CANNOT DELETE OR OVERWRITE
resource "google_storage_bucket_iam_member" "audit_notary_storage" {
  bucket = google_storage_bucket.audit_checkpoints.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.audit_notary.email}"
}

# Can SIGN audit checkpoints with asymmetric ECDSA P-256 key (SIGNER ONLY)
# Replaced broad roles/cloudkms.signerVerifier with specific roles/cloudkms.signer
resource "google_kms_crypto_key_iam_member" "audit_notary_kms_signer" {
  crypto_key_id = google_kms_crypto_key.audit_checkpoint.id
  role          = "roles/cloudkms.signer"
  member        = "serviceAccount:${google_service_account.audit_notary.email}"
}

# ─── 6. Public Verification Key Read Access (Integrated into roles/cloudkms.verifier)
# Redundant roles/cloudkms.publicKeyViewer grants removed in V20.16 because
# roles/cloudkms.verifier inherently includes cloudkms.cryptoKeyVersions.viewPublicKey.

# Inventory can verify audit checkpoint signatures (VERIFIER ONLY, CANNOT SIGN)
resource "google_kms_crypto_key_iam_member" "inventory_audit_key_verifier" {
  crypto_key_id = google_kms_crypto_key.audit_checkpoint.id
  role          = "roles/cloudkms.verifier"
  member        = "serviceAccount:${google_service_account.inventory.email}"
}
