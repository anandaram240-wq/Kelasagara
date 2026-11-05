# KELASAGARA V20.3: REVOCATION AND ACCOUNT RECOVERY
## Device Loss, Non-Biometric Recovery, and MFA Fallback Protocols

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Document Code:** KS-SEC-P20.3-10  
**Classification:** Core Security Engineering Specification

---

## 1. THE PROBLEM OF DEVICE LOSS & PERMANENT LOCKOUT

A critical vulnerability in overly rigid device-bound biometric systems is the "bricked worker" problem: if a worker loses their physical mobile device, drops it into water, or has it stolen, and device-bound signature is strictly required to perform all operations, the worker is permanently locked out of their livelihood.

**Kelasagara V20.3 solves this by separating Account Recovery from Routine Biometric Verification.**

---

## 2. RECOVERY DECISION TREE & PROTOCOLS

```
Worker loses physical device
       │
       ▼
[Step 1: Out-of-Band Identity Re-establishment]
Worker logs in on new device using Firebase Verified Phone OTP + Govt Identity (Aadhaar / National ID)
       │
       ▼
[Step 2: Non-Biometric Step-Up Proof Verification]
Backend server-side step-up proof service (`step_up_proof_service_v19.ts`) verifies
out-of-band ownership. Generates signed, single-use `DEVICE_RECOVERY_PROOF`.
       │
       ▼
[Step 3: Revocation of Lost Hardware Key]
Backend marks old device record in `/biometric_devices/{oldKeyId}` as `REVOKED`.
Old device key can never again authenticate against the account.
       │
       ▼
[Step 4: Provisioning of New Device Key]
New device generates Keystore ECDSA P-256 key pair, passes Android Key Attestation,
and registers under `/biometric_devices/{newKeyId}`.
       │
       ▼
[Step 5: Biometric 1:1 Identity Confirmation]
New device captures worker's face. Backend OpenCV SFace engine compares face against
existing AES-256-GCM encrypted biometric template from vault.
       │
  ┌────┴────┐
  │         │
  ▼         ▼
[Match]   [No Match / Impostor]
Cosine >= 0.363:                   Cosine < 0.363:
Device registration activated;     Fraud alert triggered; new device blocked;
worker account restored.           compliance officer review queue ticket filed.
```

---

## 3. AUDIT TRAILS & IMMUTABILITY

Every revocation, recovery claim, and device substitution is recorded in `/tamper_evident_audit_log` with:
- Timestamp (ISO 8601 UTC).
- Initiator UID and IP address.
- Old `deviceKeyId` and New `deviceKeyId`.
- Out-of-band proof token hash.
- Forensic compliance reason code.
