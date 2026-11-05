# KELASAGARA V20.15: TERRAFORM VARIABLES & COMPREHENSIVE PRODUCTION-DENIAL CONTROLS
# Enforces multi-layer safety invariants, allowlists, denylists, and label verifications.

variable "sandbox_project_id" {
  type        = string
  description = "The isolated Google Cloud non-production sandbox project ID. MUST NOT be a production project."

  validation {
    condition     = length(trimspace(var.sandbox_project_id)) > 0
    error_message = "CRITICAL: sandbox_project_id cannot be empty."
  }

  validation {
    condition     = can(regex("^(kelasagara|ks)-(sandbox|staging|dev|nonprod|test)-[a-z0-9]+$", var.sandbox_project_id))
    error_message = "ERROR: sandbox_project_id must match the non-production naming convention: 'kelasagara-(sandbox|staging|dev|nonprod|test)-<suffix>'."
  }

  validation {
    condition     = !contains(["kelasagara-prod", "kelasagara-production", "kelasagaara_v17", "kelasagara-live", "production", "prod"], lower(trimspace(var.sandbox_project_id)))
    error_message = "CRITICAL SECURITY VIOLATION: Production project identifier detected in sandbox_project_id denylist! Deployment halted."
  }
}

variable "allowed_project_ids" {
  type        = list(string)
  description = "Explicit allowlist of authorized non-production Google Cloud project IDs."
  default = [
    "kelasagara-sandbox-blr01",
    "kelasagara-staging-blr01",
    "kelasagara-dev-blr01",
    "kelasagara-test-blr01"
  ]
}

variable "region" {
  type        = string
  description = "Google Cloud region for regional KMS keyrings, Cloud Storage, and Firestore."
  default     = "asia-south1" # Mumbai, India
}

variable "environment" {
  type        = string
  description = "Environment identifier. Strictly restricted to non-production environments."
  default     = "sandbox"

  validation {
    condition     = contains(["sandbox", "staging", "dev", "test"], lower(var.environment))
    error_message = "ERROR: environment must be one of: sandbox, staging, dev, test. Production deployments are strictly prohibited."
  }
}

variable "expected_organization_id" {
  type        = string
  description = "Expected Google Cloud Organization ID under which the sandbox project must reside."
  default     = "109876543210" # Example non-production sandbox Org ID
}

variable "required_labels" {
  type        = map(string)
  description = "Mandatory resource labels for compliance and billing isolation."
  default = {
    managed_by  = "terraform"
    environment = "sandbox"
    subsystem   = "biometric-identity"
    compliance  = "v20-15"
    data_tier   = "confidential"
  }
}

variable "audit_retention_days" {
  type        = number
  description = "Retention period for audit checkpoints in Cloud Storage."
  default     = 90 # 90 days in non-production sandbox
}

variable "allow_bucket_lock" {
  type        = bool
  description = "Safety gate: Bucket Lock is strictly forbidden in this phase. Must remain false."
  default     = false

  validation {
    condition     = var.allow_bucket_lock == false
    error_message = "CRITICAL SAFETY VIOLATION: Irreversible Bucket Lock cannot be enabled in Phase 20.15."
  }
}
