# KELASAGARA BIOMATCH
# STAGE S8: DEVICE INTEGRITY POLICY & ATTESTATION VERDICT MATRIX

**Document ID:** `KB-POL-S8-03`  
**Classification:** Operational Security & Risk Management Policy  
**Effective Date:** Stage S8 / October 2026  
**Applicable Subsystems:** Flutter Client (`BiometricService`), Node.js Server (`DeviceAttestationService`)  
**Enforcing Invariants:** Invariant I-14, Invariant I-26  

---

## 1. Policy Overview & Scope

This policy governs device integrity enforcement for biometric enrollment and authentication within Kelasagara BioMatch. Its objective is to protect the biometric enrollment gallery against automated attacks originating from emulators, compromised OS environments, and re-packaged application binaries, while maintaining fair, non-punitive access for genuine workers across diverse device tiers in India.

---

## 2. Verdict Decision Matrix

The Node.js backend evaluates the `deviceRecognitionVerdict` array returned by the Google Play Integrity API according to the following decision tiers:

| Attestation Verdict | Google Play Integrity Signals | Platform State | Backend Action | User Impact |
|:---|:---|:---|:---:|:---|
| **`MEETS_STRONG_INTEGRITY`** | Hardware-backed keystore, hardware attestation, locked bootloader, Verified Boot. | Premium certified device (Knox, Titan M, StrongBox). | **PERMIT** | Immediate biometric capture and neural inference. |
| **`MEETS_DEVICE_INTEGRITY`** | CTS-certified Android build, Google Play Services genuine device. | Standard genuine consumer Android smartphone. | **PERMIT** | Immediate biometric capture and neural inference. |
| **`MEETS_BASIC_INTEGRITY`** | Untampered app binary, but unlocked bootloader or custom ROM. | Custom ROM / developer-unlocked device. | **STEP-UP** | Queued for administrative KYC / manual document review. |
| **`EMULATOR_HOOKING_DETECTED`** | Unrecognized environment, Frida, Xposed, Magisk, virtual camera driver, or package mismatch. | Hostile / emulated / hooked environment. | **BLOCK (403)** | Immediate HTTP 403 failure. Biometric inference aborted. |
| **`UNATTESTED_DEV_ENVIRONMENT`** | Token omitted or dev bypass header present in local development. | Hermetic test runner or local offline emulator. | **PERMIT (DEV ONLY)** | Strictly prohibited when `NODE_ENV === "production"`. |

---

## 3. Strict Production Safeguards (Invariant I-26)

1. **Zero Dev-Bypass in Production:**  
   If `NODE_ENV === "production"`, any request attempting to use `allowDevBypass = true` or submitting mock token strings (`mock_play_integrity_*`) is intercepted and rejected with verdict `EMULATOR_HOOKING_DETECTED`.
2. **Package Name Enforcement:**  
   Every attestation token MUST match the exact authoritative package name:
   ```text
   com.kelasagara.app
   ```
   Tokens issued for re-packaged or side-loaded binaries are treated as tampered and rejected.
3. **Attestation Freshness:**  
   Tokens with a timestamp delta exceeding **180,000 milliseconds (3 minutes)** are rejected to defend against replay and pre-computed token attacks.
4. **Canonical Request Hash Binding:**  
   The token must contain `requestHash = SHA-256(nonce:uid:action:captureDigest)` matching the session challenge and submitted image bytes.

---

## 4. Human Rights, DPDPA 2023 & Non-Punitive Escalation (Invariant I-14)

> [!IMPORTANT]
> **Invariant I-14 (Non-Punitive Escalation):**  
> Under no circumstances shall an automated device attestation rejection or ambiguous biometric match trigger an automatic account deletion, permanent forfeiture of accrued earnings, or police reporting.

In cases where a genuine informal worker uses a refurbished device with an unlocked bootloader (`MEETS_BASIC_INTEGRITY`):
- The app displays an informative error: *"We could not verify your device security. Please verify using government ID."*
- The worker's account transitions to `pending_review` (not `banned`).
- The worker is provided an alternative verification pathway (manual Document KYC / Aadhaar Offline XML verification).
