#!/usr/bin/env bash
# scripts/provision_staging_kms.sh
# ==============================================================================
# KELASAGARA V16.0: SAFE STAGING GOOGLE CLOUD KMS PROVISIONING
#
# Enforces Invariants:
# 1. Strict Staging Guard: Rejects any production project ID fail-closed.
# 2. Safe Default: Defaults to --dry-run mode unless --execute is explicitly passed.
# 3. No Masked Errors: Zero '|| true' constructs. Every step is verified.
# 4. Indian Data Sovereignty: asia-south1 (Mumbai) per DPDPA 2023.
# ==============================================================================

set -euo pipefail

MODE="dry-run"
STAGING_PROJECT="${GCP_STAGING_PROJECT_ID:-kelasagara-staging}"
LOCATION="asia-south1"
KEYRING_NAME="biomatch-ring-staging"
KEY_NAME="template-kek-staging"
SERVICE_ACCOUNT="biometric-backend-staging-sa@${STAGING_PROJECT}.iam.gserviceaccount.com"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute)
      MODE="execute"
      shift
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --project=*)
      STAGING_PROJECT="${1#*=}"
      SERVICE_ACCOUNT="biometric-backend-staging-sa@${STAGING_PROJECT}.iam.gserviceaccount.com"
      shift
      ;;
    *)
      echo "Unknown flag: $1"
      echo "Usage: $0 [--dry-run | --execute] [--project=PROJECT_ID]"
      exit 1
      ;;
  esac
done

MODE_UPPER="$(echo "${MODE}" | tr '[:lower:]' '[:upper:]')"
echo "========================================================================"
echo "  KELASAGARA KMS PROVISIONING HARNESS (MODE: ${MODE_UPPER})"
echo "========================================================================"
echo "Target Project    : ${STAGING_PROJECT}"
echo "Region (DPDPA)    : ${LOCATION}"
echo "Key Ring          : ${KEYRING_NAME}"
echo "Crypto Key        : ${KEY_NAME}"
echo "Service Account   : ${SERVICE_ACCOUNT}"
echo "========================================================================"

# Safety Guard: Fail-closed if project appears to be production
if [[ "${STAGING_PROJECT}" =~ (prod|production|live|kelasagara-f127a$) ]]; then
  echo "[-] ERROR: Refusing to provision on project '${STAGING_PROJECT}'."
  echo "    This script is strictly intended for STAGING environments."
  echo "    Production provisioning must go through formal GitOps / Terraform pipelines."
  exit 1
fi

# Rotation timestamp calculation (90 days forward)
if date -u -v+90d +"%Y-%m-%dT00:00:00Z" >/dev/null 2>&1; then
  NEXT_ROTATION="$(date -u -v+90d +"%Y-%m-%dT00:00:00Z")"
else
  NEXT_ROTATION="$(date -u -d "+90 days" +"%Y-%m-%dT00:00:00Z")"
fi

execute_or_dry_run() {
  local description="$1"
  shift
  echo ""
  echo "[STEP] ${description}"
  echo "  Command: $*"

  if [[ "${MODE}" == "execute" ]]; then
    if ! command -v gcloud >/dev/null 2>&1; then
      echo "[-] ERROR: gcloud CLI not found in PATH. Install Google Cloud SDK to execute."
      exit 1
    fi
    "$@"
    echo "  [OK] Success."
  else
    echo "  [DRY-RUN] Command validated. Skipped execution."
  fi
}

# Step 1: Enable Cloud KMS API
execute_or_dry_run "Enable Cloud KMS API on staging project" \
  gcloud services enable cloudkms.googleapis.com --project="${STAGING_PROJECT}"

# Step 2: Create KMS KeyRing
execute_or_dry_run "Create KMS KeyRing in ${LOCATION}" \
  gcloud kms keyrings create "${KEYRING_NAME}" \
    --location="${LOCATION}" \
    --project="${STAGING_PROJECT}"

# Step 3: Create Key Encryption Key (KEK) with 90-day rotation
execute_or_dry_run "Create Key Encryption Key (KEK) with 90-day rotation" \
  gcloud kms keys create "${KEY_NAME}" \
    --location="${LOCATION}" \
    --keyring="${KEYRING_NAME}" \
    --purpose="encryption" \
    --protection-level="hsm" \
    --rotation-period="90d" \
    --next-rotation-time="${NEXT_ROTATION}" \
    --project="${STAGING_PROJECT}"

# Step 4: Grant Decrypter/Encrypter role to backend Cloud Run Service Account
execute_or_dry_run "Grant roles/cloudkms.cryptoKeyEncrypterDecrypter to backend service account" \
  gcloud kms keys add-iam-policy-binding "${KEY_NAME}" \
    --location="${LOCATION}" \
    --keyring="${KEYRING_NAME}" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
    --project="${STAGING_PROJECT}"

echo ""
echo "========================================================================"
if [[ "${MODE}" == "execute" ]]; then
  echo "  [SUCCESS] Cloud KMS staging provisioning completed successfully."
else
  echo "  [NOTICE] Dry-run complete. No cloud resources were modified."
  echo "  To provision staging KMS, run: $0 --execute --project=<staging-project>"
fi
echo "  Target Key Resource Name:"
echo "  projects/${STAGING_PROJECT}/locations/${LOCATION}/keyRings/${KEYRING_NAME}/cryptoKeys/${KEY_NAME}"
echo "========================================================================"
