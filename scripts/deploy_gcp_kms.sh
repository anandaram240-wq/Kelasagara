#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-kelasagara-prod}"
LOCATION="asia-south1" # Mumbai data residency for Indian DPDPA compliance
KEYRING_NAME="kelasagara-biometrics"
KEY_NAME="biometric-vault-kek"

# Cross-platform BSD (macOS) and GNU (Linux) 90-day rotation timestamp calculation
if date -u -v+90d +"%Y-%m-%dT00:00:00Z" >/dev/null 2>&1; then
  NEXT_ROTATION="$(date -u -v+90d +"%Y-%m-%dT00:00:00Z")"
else
  NEXT_ROTATION="$(date -u -d "+90 days" +"%Y-%m-%dT00:00:00Z")"
fi

echo "[1/4] Enabling Cloud KMS API on project ${PROJECT_ID}..."
gcloud services enable cloudkms.googleapis.com --project="$PROJECT_ID" || true

echo "[2/4] Creating KMS KeyRing ${KEYRING_NAME} in ${LOCATION}..."
gcloud kms keyrings create "$KEYRING_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" 2>/dev/null || true

echo "[3/4] Creating HSM-backed Key Encryption Key (KEK) ${KEY_NAME}..."
gcloud kms keys create "$KEY_NAME" \
  --location="$LOCATION" \
  --keyring="$KEYRING_NAME" \
  --purpose="encryption" \
  --protection-level="hsm" \
  --rotation-period="90d" \
  --next-rotation-time="$NEXT_ROTATION" \
  --project="$PROJECT_ID" 2>/dev/null || true

echo "[4/4] Granting IAM permissions to Cloud Run Service Account..."
SERVICE_ACCOUNT="biometric-backend-sa@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud kms keys add-iam-policy-binding "$KEY_NAME" \
  --location="$LOCATION" \
  --keyring="$KEYRING_NAME" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
  --project="$PROJECT_ID" 2>/dev/null || true

echo "KMS Provisioning Complete: projects/${PROJECT_ID}/locations/${LOCATION}/keyrings/${KEYRING_NAME}/cryptoKeys/${KEY_NAME}"
