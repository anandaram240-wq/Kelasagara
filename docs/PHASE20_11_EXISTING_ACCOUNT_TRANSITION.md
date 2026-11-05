# PHASE 20.11: EXISTING ACCOUNT TRANSITION POLICY
**Role:** Principal Biometric Systems Architect & Backend Security Engineer  
**System:** Kelasagara Multi-Factor Biometric Identity Platform  
**Branch:** `security/phase20.11-legacy-template-isolation`  
**Date:** November 1, 2026  

---

## 1. OBJECTIVE & NON-DESTRUCTIVE GUARANTEE

The transition to Canonical V2 preprocessing must protect two competing security requirements:
1. **Zero False Duplicate Interference:** Existing accounts with legacy or unaligned templates must not trigger false duplicate blocks on new worker enrollments.
2. **Account Preservation & Service Continuity:** Existing accounts must NOT be deleted, locked out, or arbitrarily invalidated.

---

## 2. POLICY RULES FOR EXISTING ACCOUNTS

### Rule 1: Exclusion from 1:N Deduplication
Existing templates categorized as `DEFECTIVE_FULL_PHOTO_SFACE_V10`, `LEGACY_LANDMARK_SPACE`, or `LEGACY_TEMPLATE_UNKNOWN` are excluded from 1:N deduplication queries for new registrants. They remain in `biometric_vault` but will never match against a Canonical V2 probe vector.

### Rule 2: 1:1 Authentication Fallback
When an existing user with a legacy template attempts 1:1 facial biometric login:
- The probe vector captured by the updated client will be in Canonical V2 space.
- Because cross-space comparison is prohibited (`NEVER_COMPARE`), the 1:1 biometric match cannot be computed directly.
- **Fail-Safe Fallback:** The application prompts the worker to authenticate using their secondary credentials (registered phone number OTP or password).
- Upon successful secondary authentication, the user is immediately prompted with an in-app banner to upgrade their face template.

### Rule 3: Re-Enrollment & Authorized Replacement Flow
To upgrade an existing template to Canonical V2:
1. **Independent Identity Verification:** The user must possess an active, authenticated session with recent sign-in proof (issued within 15 minutes) or complete an OTP verification.
2. **Authorized Replacement Reservation:** An operation reservation is created with `workflowType = 'AUTHORIZED_REPLACEMENT'`, recording the user's `existingEnrollmentId`.
3. **Atomic Replacement:**
   - In a single Firestore transaction:
     - The old legacy record is marked `status: 'SUPERSEDED'`, `revokedAtMs: Date.now()`, and `supersededByEnrollmentId: newEnrollmentId`.
     - The new Canonical V2 record is committed with `status: 'ACTIVE'`, `embeddingSpaceId: 'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2'`.
   - **Zero Ghost Records:** The user maintains exactly one active template at all times, preventing duplicate gallery records.

---

## 3. AUDIT TRAIL & COMPLIANCE

Every template transition records:
- Predecessor `enrollmentId`
- Successor `enrollmentId`
- Transition timestamp and executing `operationId`
- Cryptographic signature receipt issued by `BiometricOperationReceiptService`
