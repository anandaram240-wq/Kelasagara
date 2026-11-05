# KELASAGARA V20.15: TERRAFORM PROVIDER, WORKSPACE CHECKS & MULTI-LAYER SAFETY GATES
# Enforces exact provider version pinning, workspace denial, and project allowlisting.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.20.0" # Strictly pinned version
    }
  }

  # Remote state backend must target an isolated non-production location.
  # Production state backends are strictly rejected by policy.
}

provider "google" {
  project = var.sandbox_project_id
  region  = var.region
}

locals {
  # 1. Denylist detection
  is_production_denied = (
    var.sandbox_project_id == "kelasagara-prod" ||
    var.sandbox_project_id == "kelasagara-production" ||
    var.sandbox_project_id == "kelasagaara_v17" ||
    var.sandbox_project_id == "kelasagara-live" ||
    var.environment == "production" ||
    var.environment == "prod"
  )

  # 2. Workspace check: Production workspace names are prohibited
  is_workspace_denied = (
    terraform.workspace == "prod" ||
    terraform.workspace == "production"
  )

  # 3. Allowlist validation
  is_project_allowed = contains(var.allowed_project_ids, var.sandbox_project_id)
}

# Gate 1: Production Identifier Block
resource "null_resource" "production_safety_gate" {
  lifecycle {
    precondition {
      condition     = !local.is_production_denied
      error_message = "CRITICAL SAFETY GATE: Production project deployment is strictly forbidden by KELASAGARA V20.15 policy."
    }
  }
}

# Gate 2: Workspace Safety Block
resource "null_resource" "workspace_safety_gate" {
  lifecycle {
    precondition {
      condition     = !local.is_workspace_denied
      error_message = "CRITICAL SAFETY GATE: Workspace '${terraform.workspace}' matches production convention. Prohibited."
    }
  }
}

# Gate 3: Project Allowlist Verification
resource "null_resource" "allowlist_safety_gate" {
  lifecycle {
    precondition {
      condition     = local.is_project_allowed
      error_message = "CRITICAL SAFETY GATE: Project ID '${var.sandbox_project_id}' is not present in allowed_project_ids."
    }
  }
}
