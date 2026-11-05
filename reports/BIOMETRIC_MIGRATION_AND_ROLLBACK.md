# KELASAGARA BIOMETRIC ENGINE
## Biometric Migration, Compatibility & Emergency Rollback Runbook

**Document Date:** October 23, 2026  
**Status:** VALIDATED & TESTED (MIG-01 through MIG-05)  
**Governing Standard:** ISO/IEC 24745 §7.3, NIST SP 800-88 Rev. 1  

---

## 1. Multi-Version Biometric Template Compatibility Matrix

| Stored Template Version | Original Extractor | Vector Space | Supported by SFace 1:1 Matcher? | Migration Method | Rollback Target |
| :--- | :--- | :---: | :---: | :--- | :--- |
| **`v1_landmark_raw`** | 48-D Landmark Euclidean | $\mathbb{R}^{48}$ | **NO** ($s \approx 0$) | On-Demand Lazy Profile Re-Enrollment | Flagged `MIGRATION_REQUIRED` |
| **`v2_whitened`** | 128-D Gram-Schmidt | $\mathbb{S}^{127}_{\text{Geom}}$ | **NO** ($s \approx 0$) | On-Demand Lazy Profile Re-Enrollment | Flagged `MIGRATION_REQUIRED` |
| **`v3_whitened`** | 128-D Procrustes + Fourier | $\mathbb{S}^{127}_{\text{Geom}}$ | **NO** ($s \approx 0$) | On-Demand Lazy Profile Re-Enrollment | Flagged `MIGRATION_REQUIRED` |
| **`v5_indicface_int8`** | IndicFace MobileFaceNet | $\mathbb{S}^{127}_{\text{Indic}}$ | Experimental | Batch KMS AAD Re-wrapping (MIG-02) | Standalone local fallback |
| **`sface_opencv_zoo_v1_primary`** | SFace 2021dec ONNX | $\mathbb{S}^{127}_{\text{SFace}}$ | **YES** (Authoritative) | Native State (No migration needed) | Current Authoritative Target |

---

## 2. Idempotent Migration State Machine (Stage S8)

All 5 migration requirements verified in `Stage S8`:

```
                 [ CANDIDATE RECORD: biometric_vault/{uid} ]
                                     │
                 ┌───────────────────┴───────────────────┐
                 ▼                                       ▼
         [ DRY-RUN MODE ]                        [ LIVE MIGRATION ]
         ├── Verify Ciphertext Integrity         ├── Verify Ciphertext Integrity
         ├── Inspect Envelope Version            ├── Decrypt with Current Key Provider
         ├── Compute Canonical Binary AAD        ├── Construct Length-Prefixed Binary AAD
         └── Preview Output (MIG-01)             ├── Re-encrypt with v3 Cloud KMS
             (Original unchanged)                ├── Atomic Merge Commit (MIG-02)
                                                 └── Audit: TEMPLATE_MIGRATED_V3
```

- **MIG-03 Idempotency:** If a document already carries `envelopeVersion === 'v3_kms_gcm'` and `modelVersion === 'sface_opencv_zoo_v1_primary'`, the migration engine skips processing with zero overhead.
- **MIG-04 Corruption Resilience:** If source ciphertext fails authentication tag validation, the migration engine aborts immediately, leaving the original record intact and logging a critical alert without corrupting state.

---

## 3. On-Device Lazy Re-Enrollment (`FaceReEnrollTile`)

For workers enrolled under legacy geometric representations:
1. **Background Detection:** Upon worker login, backend detects `modelVersion !== 'sface_opencv_zoo_v1_primary'`.
2. **Profile Prompt:** The mobile application displays `FaceReEnrollTile` in `lib/screens/profile/profile_screen.dart` with notice:  
   *ಮುಖ ಮರು-ನೋಂದಣಿ (Re-enroll Face ID — updated security).*
3. **Owner Verification:** Worker blinks to authenticate ownership (`BlinkVerifySheet`).
4. **Instant SFace Capture:** Mobile camera captures high-quality ISO 29794-5 face; backend extracts authoritative SFace 128-d vector.
5. **Cross-Account Check:** Backend executes 1:N screening against other accounts to ensure no multi-account collision.
6. **Atomic Overwrite:** Stored template upgraded to SFace; account status retained.

---

## 4. Emergency Rollback Runbook

### 4.1 Scenario A: Cloud KMS Outage or Network Disconnect
- **Symptom:** Backend throws `KMS_UNAVAILABLE_ERROR` during template decryption or encryption.
- **Enforced Security Policy:** **FAIL-CLOSED**. The backend does NOT write unencrypted templates to Firestore.
- **Circuit Breaker:** Returns `HTTP 503 Service Unavailable` with `status: 'technical_failure_retry'`.
- **Worker Fallback:** The mobile app informs the user and routes them to SMS OTP authentication.

### 4.2 Scenario B: Rollback of Firestore Security Rules
- **Rule Boundary:** Under NO circumstances should `biometric_vault/{uid}` be reverted to `allow read: if isSignedIn();`.
- **Maintenance Access:** If manual investigation of vault documents is required by platform administrators, access must be conducted exclusively via Firebase Admin SDK CLI scripts using authorized service account keys in a secure bastion environment.
