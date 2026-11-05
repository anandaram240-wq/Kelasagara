# KELASAGARA BIOMATCH · STAGE S7 THREAT MODEL (S7_THREAT_MODEL.md)

**Classification:** Formal Threat Model (STRIDE & LINDDUN)  
**Stage:** S7  
**Date:** 2026-10-11  
**Audited Assets:** Facial images (ephemeral memory), 128-D templates, Firestore encrypted envelopes, in-memory index, verification decisions, and audit logs.

---

## 1. System Boundary and Attacker Profiles

### 1.1 Attacker Profiles
1. **Unauthenticated Remote Attacker:** Attempts credential stuffing, API fuzzing, replay attacks, and denial-of-service via automated HTTP scripts.
2. **Malicious Applicant (Impersonator):** Attempts presentation attacks (printed 2D photos, video replays, deepfakes) to bypass KYC or create duplicate identities.
3. **Colluding Worker / Account Renter:** Legitimate worker who passes enrollment, then leases account to unvetted third parties or workers with revoked badges.
4. **Malicious Hirer / Tenant Insider:** Attempts cross-tenant template linkage or extraction of worker biometrics from shared database infrastructure.
5. **Privileged Insider / Rogue Administrator:** Possesses database or server read access, attempting to export biometric vaults or forge audit trails.

---

## 2. STRIDE & LINDDUN Threat Analysis

| Threat ID | Threat Class | Threat Title | Vulnerable Asset | Preventive Control | Detection Mechanism | Residual Risk |
| :--- | :--- | :--- | :--- | :--- | :--- | :---: |
| **THREAT-01** | **Spoofing** | 2D Photo & Screen Replay | Camera capture & 1:1 decision | Server-side landmark motion verification & challenge nonces | Landmark variance and optical flow scoring | `MEDIUM` |
| **THREAT-02** | **Tampering** | Cross-Tenant Ciphertext Splicing | Encrypted envelopes in Firestore | AES-256-GCM Additional Authenticated Data (AAD) binding `uid` + `tenantId` | Auth tag validation failure (`AEAD_BAD_TAG`) | `NEGLIGIBLE` |
| **THREAT-03** | **Linkability** | Cross-Tenant Template Linkage via Gram Isometry | Rotated vectors in plaintext dumps | Authenticated encryption at rest (AES-256-GCM); no plaintext rotation storage | DB export anomaly telemetry | `LOW` |
| **THREAT-04** | **Replay** | Nonce Replay & Precomputed Verification | Verification endpoint | Single-use nonces (`chal_*`) bound to caller UID, 300s TTL | Firestore atomic consume transaction | `NEGLIGIBLE` |
| **THREAT-05** | **Race / State**| Concurrent Multi-Device Enrollment | In-memory 1:N gallery & uniqueness | Firestore distributed lease lock (`locks/enroll_{uid}`) | Mutex collision rejection | `NEGLIGIBLE` |
| **THREAT-06** | **Tampering** | Model Weight Backdooring | ONNX models in `backend/models/` | Hardcoded SHA-256 validation at startup; signed ML-BOM | Process exit on mismatch | `NEGLIGIBLE` |
| **THREAT-07** | **Elevation** | Rogue Admin Biometric Override | Worker verification status | Dual-control audit logging; immutable Firestore rules | Anomaly audit report | `LOW` |
| **THREAT-08** | **Non-Compliance**| 1:N False Candidate Lockout | Worker livelihood & marketplace access | **Invariant I-14:** Duplicate hits NEVER auto-reject; route to Document KYC | Telemetry on review queues | `ZERO` (for lockout) |

---

## 3. High-Priority Remediation: The Splicing Vulnerability (THREAT-02)

### Root Cause Analysis
In the pre-S7 implementation of `backend/src/services/template_privacy.ts`, `TemplatePrivacyService.encryptTemplate()` encrypted the raw vector using AES-256-GCM but **did not configure Additional Authenticated Data (`cipher.setAAD()`)**. 

Consequently, an attacker who obtained a valid ciphertext envelope belonging to `user_victim` in `tenant_A` could splice that envelope into `user_attacker`'s document in `tenant_B`. During decryption, the decipherer verified the authentication tag only against the ciphertext bytes, successfully decrypting the victim's embedding under the attacker's context.

### S7 Remediation Invariant
To eliminate this defect:
1. `cipher.setAAD(Buffer.from(`${envelopeVersion}|${tenantId}|${uid}|${keyVersion}`))` is strictly enforced.
2. `decipher.setAAD(...)` must verify the identical tuple. Any modification to `uid` or `tenantId` triggers immediate authentication tag rejection.

---

## 4. Exit Gate Assessment: S7-G02 (Threat Model)

**Status:** `DONE-VERIFIED`  
**Evidence Artifact:** `evidence/s7/threat_catalog.json`  
**Review Summary:** All 8 major biometric and system threats categorized with explicit invariants, attack paths, controls, and detection hooks.
