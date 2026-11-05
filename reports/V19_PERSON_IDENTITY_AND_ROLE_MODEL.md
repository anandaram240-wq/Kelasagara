# V19 Person Identity and Role Model

## 1. Identity & Account Entities
To maintain rigorous separation of concerns and avoid coupling mathematical face vectors to human identity, the system defines 5 distinct identifier layers:

```
┌────────────────────────────────────────────────────────┐
│ 1. Person Identity: personId                           │
│    (Authoritative human entity in Kelasagara registry) │
└──────────────────────────┬─────────────────────────────┘
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
┌───────────────────────────┐ ┌───────────────────────────┐
│ 2. Auth Identity: authUid │ │ 3. Role Identifiers:      │
│    (Firebase Auth token)  │ │    workerId / hirerId     │
└────────────┬──────────────┘ └───────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────┐
│ 4. Biometric Enrollment: biometricEnrollmentId          │
│    (Scoped to template lifecycle: chal_*, salt, epoch)  │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│ 5. Template & Model Metadata:                           │
│    modelVersion: 'sface_2021dec_128d_v1'                │
│    templateVersion: 'v3_kms_gcm'                        │
│    enrollmentStatus: PENDING_FACE -> REVIEW -> ACTIVE   │
└─────────────────────────────────────────────────────────┘
```

## 2. Multi-Role Policy & Fraud vs Legitimate Role Linking
- **The Core Rule:** A single living human may legitimately participate in the marketplace as both a **Worker** (providing services) and a **Hirer** (contracting services).
- **Legitimate Role Linking:** When an authenticated user with an active Worker account creates a Hirer profile (or vice versa), the system verifies the existing `authUid` and links the new role profile to the existing `personId`. The biometric template in `biometric_vault/{uid}` remains unified and is not flagged as a duplicate.
- **Cross-Account Collision (Duplicate Account):** When an unauthenticated or distinct `authUid` presents a facial vector matching an existing enrolled user ($\text{Cosine Sim} \ge 0.74$), the system treats it as a duplicate registration attempt across distinct accounts. It does not auto-link accounts without verified credential recovery (OTP to original phone).

## 3. Storage Separation & PII Minimization in Biometric Vault
1. **`users/{uid}`**: Authoritative application user document containing `name`, `phoneNumber`, `role`, `accountStatus`, and `faceVerified: boolean`.
2. **`biometric_vault/{uid}`**:
   - Stores ONLY:
     * `ciphertext`: AES-256-GCM encrypted 128-D embedding.
     * `envelopeVersion`: `'v3_kms_gcm'`.
     * `salt`, `iv`, `tag`: Cryptographic nonces.
     * `phoneNumberMasked`: E.g., `+91 ******5177` (used solely for duplicate collision disambiguation hints).
     * `modelId`: `'sface_2021dec_128d_v1'`.
     * `enrolledAtMs`, `updatedAtMs`.
   - Strictly Omits: Raw worker name, cleartext residential address, GPS location history, raw facial imagery.
   - Access Control: Firestore Security Rules deny all client read and write operations (`allow read, write: if false;`). Only backend Admin SDK can access the vault.
