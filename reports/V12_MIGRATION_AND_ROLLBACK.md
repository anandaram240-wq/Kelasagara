# KELASAGARA BIOMETRIC ENGINE V12.0
## Migration, Compatibility & Rollback Strategy

**Date:** October 23, 2026  
**Status:** VALIDATED & IDEMPOTENT  
**Governing Standard:** ISO/IEC 24745 §7.3, NIST SP 800-88 Rev. 1  

---

## 1. Migration Architecture: The Multi-Version State Machine

Migrating production biometric records requires preserving worker authentication availability while upgrading legacy v1/v2 envelopes to `v3_kms_gcm` and migrating geometric templates to deep SFace vectors.

### 1.1 State Machine States
```
 [ LEGACY RECORD ]
   ├── v1_plaintext / v2_aes_gcm
   └── modelVersion: legacy / null
          │
          ├── Dry-Run Mode (MIG-01) ──► Non-destructive validation preview
          │
          ▼ Live Migration Execution (MIG-02)
   ┌───────────────────────────────────────────┐
   │ 1. Decrypt legacy envelope using DEK      │
   │ 2. Construct Length-Prefixed Binary AAD   │
   │ 3. Encrypt with v3 Cloud KMS Provider     │
   │ 4. Atomic Write to biometric_vault/{uid}  │
   │ 5. Audit Log: TEMPLATE_MIGRATED_V3        │
   └───────────────────────────────────────────┘
          │
          ▼
 [ UPGRADED V3 KMS RECORD ]
   ├── Envelope: v3_kms_gcm
   └── Status: IDEMPOTENT (MIG-03: Re-runs safely skipped)
```

### 1.2 Verification of Migration Tests
All 5 automated migration state tests passing in `Stage S8`:
- **MIG-01:** Dry-run migration previews v2 $\to$ v3 conversion without altering original document (7.06 ms).
- **MIG-02:** Live migration commits valid `v3_kms_gcm` record and preserves vector fidelity (3.80 ms).
- **MIG-03:** Re-migrating an already-migrated v3 record is idempotent and safely skipped (0.23 ms).
- **MIG-04:** Migration fails safely when source ciphertext is corrupted without damaging existing state (3.89 ms).
- **MIG-05:** Batch migration handles heterogeneous envelope batches seamlessly (6.84 ms).

---

## 2. On-Device Lazy Re-Enrollment Strategy

For legacy accounts whose stored templates are 48-D geometric embeddings rather than deep SFace representations:
1. **Detection:** When a user logs in, the backend checks `vaultDoc.modelVersion`.
2. **Graceful Flagging:** If `modelVersion !== 'sface_opencv_zoo_v1_primary'`, the backend issues a temporary session claim `biometric_upgrade_required`.
3. **Seamless UX:** The mobile application presents the user with `FaceReEnrollTile` on their profile dashboard.
4. **Instant Upgrade:** The user completes a 5-second liveness blink capture; the new SFace template is written, instantly retiring the legacy record without disrupting account history, earnings, or ratings.

---

## 3. Disaster Recovery & Rollback Procedures

### 3.1 Cloud KMS Outage or Unavailability
If Google Cloud KMS experiences an outage or network partition:
- The backend detects `KMS_UNAVAILABLE_ERROR` (verified in Stage S8 Test 9).
- **Fail-Closed Policy:** The backend does **not** degrade to storing unencrypted templates in Firestore.
- **Circuit Breaker:** The server returns `HTTP 503 SERVICE_UNAVAILABLE` with status `technical_failure_retry`.
- Mobile clients notify workers: *"ಪರಿಶೀಲನೆ ಸರ್ವರ್ ತಾತ್ಕಾಲಿಕವಾಗಿ ಲಭ್ಯವಿಲ್ಲ — Verification service temporarily unavailable. Please use SMS OTP login."*

### 3.2 Rollback of `firestore.rules` (Emergency Protocol)
If an unexpected edge case requires rolling back Firestore security rules:
- `allow read, write: if false;` on `biometric_vault/{uid}` must **NEVER** be reverted to `allow read: if isSignedIn();`.
- If client access is required for administrative maintenance, it must be performed strictly via Firebase Admin SDK CLI scripts using service account credentials.
