# KELASAGARA BIOMETRIC ENGINE V12.0
## Privacy, Legal Compliance & Regulatory Review

**Date:** October 23, 2026  
**Status:** COMPLIANT  
**Governing Laws & Standards:** India Digital Personal Data Protection Act (DPDPA) 2023, Aadhaar Act 2016 (Architectural Principles), ISO/IEC 24745:2022  

---

## 1. Compliance with the Digital Personal Data Protection Act (DPDPA) 2023

### 1.1 Purpose Limitation (DPDPA §6)
Biometric data (facial images and extracted 128-d templates) is processed solely for:
1. One-to-one identity verification of workers at shift check-in and account login.
2. One-to-many duplicate account screening to prevent registration fraud and wage theft.
Biometric data is **never** monetized, shared with third-party advertisers, or used for surveillance.

### 1.2 Informed, Multilingual Consent Notice (DPDPA §6(1))
Prior to camera activation, the worker is presented with an explicit, bilingual notice in Kannada and English:
- *ಕನ್ನಡ:* "ನಿಮ್ಮ ಗುರುತನ್ನು ದೃಢೀಕರಿಸಲು ಮತ್ತು ನಕಲಿ ಖಾತೆಗಳನ್ನು ತಡೆಯಲು ನಿಮ್ಮ ಮುಖದ ವಿವರಗಳನ್ನು ಸುರಕ್ಷಿತವಾಗಿ ಬಳಸಲಾಗುತ್ತದೆ. ನೀವು ಯಾವುದೇ ಸಮಯದಲ್ಲಿ ಇದನ್ನು ಅಳಿಸಬಹುದು."
- *English:* "Your facial data is securely processed to verify your identity and prevent duplicate accounts. You may delete your biometric record at any time."

### 1.3 Right to Erasure / Right to be Forgotten (DPDPA §12(3))
The system provides a certified cryptographic erasure workflow:
- **API Endpoint:** `DELETE /api/biometrics/template?targetUid={uid}`.
- **Actions Executed:**
  1. Authenticates caller ownership via Firebase ID Token.
  2. Overwrites template ciphertext in `biometric_vault/{uid}` with random zeros.
  3. Deletes document from Firestore.
  4. Evicts entry from `InMemoryBiometricIndex`.
  5. Appends immutable `BIOMETRIC_TEMPLATE_DELETED` audit record.
  6. Updates user record: `faceVerified: false`, `accountStatus: 'unverified'`.

### 1.4 Protection of Data & Privacy Masking (DPDPA §8(3))
When a duplicate registration is blocked:
- The existing user's phone number is masked: `+91 ******7890`.
- The existing user's Firebase UID is masked: `xK9***wXy`.
- Raw embeddings and high-resolution photos are strictly prevented from returning to client UI.

---

## 2. Distinction from UIDAI Aadhaar Infrastructure

To maintain complete legal and operational integrity:
1. **No Impersonation or Equivalence Claims:** Kelasagara explicitly states that its Biometric Engine is an independent, proprietary platform inspired by the public architectural separation of Aadhaar Face RD. It does NOT claim to be certified by STQC or affiliated with UIDAI.
2. **Authorized UIDAI Integration Boundary:** An official UIDAI Face RD integration will be activated solely if and when Kelasagara is formally registered as an Authentication User Agency (AUA) / Sub-AUA and provided with authorized STQC credentials.
3. **Independent Identity Namespace:** All identities, keys, nonces, and vaults belong exclusively to the Kelasagara platform.

---

## 3. ISO/IEC 24745:2022 Biometric Information Protection

| ISO 24745 Requirement | System Implementation | Verification Evidence |
| :--- | :--- | :--- |
| **Confidentiality (§6.2)** | Sealed Firestore rules (`allow read, write: if false;`); AES-256-GCM envelope encryption. | Security Containment Report (Part 3) |
| **Integrity (§6.3)** | Length-prefixed binary canonical AAD; SHA-256 tamper-evident hash-chained audit logs. | Stage S8 Cryptographic Suite |
| **Irreversibility (§6.4)** | Raw pixel buffers zeroed in RAM immediately after inference; deep CNN embeddings are lossy non-invertible projections. | DPDPA Memory Zero-Out in Dart / C++ |
| **Unlinkability (§6.5)** | Each tenant context binds distinct canonical AAD, preventing cross-tenant template correlation. | KMS AAD Tenant Context Tests |
