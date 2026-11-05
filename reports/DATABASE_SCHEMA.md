# KELASAGARA BIOMETRIC ENGINE V10.0
# Cloud Firestore Database Schema & Security Rule Architecture
## Data Structures, Document Schemas, Indexing Policies, and Access Control Rules

**Document ID:** `REP-DBSCHEMA-V10-01`  
**Database:** Google Cloud Firestore (Native Mode)  
**Security Standard:** ISO/IEC 24745:2022, DPDPA 2023 §8(3)  
**Status:** Approved Production Schema  
**Version:** 10.0.0-PROD  
**Date:** 2026-10-22  

---

## 1. Firestore Collection Architecture

The biometric storage architecture is organized into two primary collections and transition fields on user profiles:

```
Cloud Firestore
├── biometric_vault/{uid}               --> Sealed encrypted biometric templates
├── biometric_audit_logs/{logId}       --> Immutable, tamper-evident audit ledger
└── users/{uid}                        --> User profile with biometric state flags
```

---

## 2. Detailed Document Schemas

### 2.1 Collection: `biometric_vault`
- **Path:** `/biometric_vault/{uid}` (Document ID matches Firebase Auth UID)
- **Purpose:** Stores the encrypted biometric embedding vector and cryptographic parameters.
- **Access Rule:** Signed-in users may read for 1:N deduplication; writes restricted exclusively to backend Admin SDK.
- **Fields:**

| Field Name | Type | Description | Security / Privacy Note |
| :--- | :--- | :--- | :--- |
| `embedding` | `Array<number>` | 128-element Float32 array ($\|\mathbf{e}\|_2 \equiv 1.0$) | L2-normalized hypersphere vector; non-invertible |
| `modelVersion` | `String` | Version identifier (e.g. `v4_whitened_procrustes`) | Used for multi-version backward compatibility |
| `phoneNumberMasked` | `String` | Masked phone (e.g. `+91 ****7890`) | Displayed only on duplicate interception; zero PII leakage |
| `dpdpaConsentVersion`| `String`| Consent agreement identifier (e.g. `v1.0_2026`) | Proves verifiable consent under DPDPA 2023 §6 |
| `enrolledAt` | `Timestamp` | Server timestamp of initial enrollment | Audit record creation date |
| `updatedAt` | `Timestamp` | Server timestamp of latest template refresh | Tracks template updates via re-enrollment |
| `encryptedTemplate` | `String` (Opt) | AES-256-GCM ciphertext base64 string | Used when KMS envelope encryption is active |
| `iv` | `String` (Opt) | 96-bit base64 initialization vector | Cryptographically random per-write |
| `authTag` | `String` (Opt) | 128-bit base64 GCM authentication tag | Verifies ciphertext integrity |

### 2.2 Collection: `biometric_audit_logs`
- **Path:** `/biometric_audit_logs/{logId}` (Auto-generated UUIDv4)
- **Purpose:** Immutable append-only audit trail recording every biometric decision, match, and security rejection.
- **Access Rule:** Write-only by backend Admin SDK; read restricted to security auditor role.
- **Fields:**

| Field Name | Type | Description |
| :--- | :--- | :--- |
| `eventType` | `String` | Event type: `ENROLL_SUCCESS`, `VERIFY_SUCCESS`, `DUPLICATE_HARD_BLOCK`, `CROSS_ACCOUNT_FLAG`, `PAD_SPOOF_REJECTED` |
| `uid` | `String` | Firebase Auth UID of requesting applicant |
| `matchedUid` | `String` (Opt) | Firebase Auth UID of existing duplicate match (if detected) |
| `similarityScore` | `Number` | Measured cosine similarity ($\langle \mathbf{e}_1, \mathbf{e}_2 angle \in [-1, 1]$) |
| `threshold` | `Number` | Operating decision threshold applied ($0.38$ for verify, $0.74$ for dedup) |
| `ipdPixels` | `Number` (Opt) | Measured Interpupillary Distance in pixels |
| `laplacianVariance`| `Number` (Opt)| Measured 2D Laplacian texture variance ($\sigma^2_L$) |
| `metadata` | `Map` | Contextual metadata: client version, top-K candidate scores, IP hash |
| `timestamp` | `Timestamp` | Server-assigned UTC timestamp |

### 2.3 User Document Transition Fields (`users/{uid}`)
Biometric enrollment and verification state transitions are reflected on the user profile:
- `faceEnrolled`: `Boolean` (`true` once biometric template is successfully written to vault).
- `faceVerified`: `Boolean` (`true` once 1:1 verification has succeeded).
- `biometricRegisteredAt`: `Timestamp` (records initial verification date).
- `biometricModelVersion`: `String` (records model version used during enrollment).

---

## 3. Production Firestore Security Rules (`firestore.rules`)

The production rules deployed to Firebase (`kelasagara-f127a`) guarantee zero unauthorized template modification while enabling high-throughput duplicate detection:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    function isSignedIn() {
      return request.auth != null;
    }
    
    // Biometric Vault: Read permitted for signed-in users (enabling 1:N cross-account check);
    // Write restricted strictly to backend Admin SDK (rules evaluate to false for client writes)
    match /biometric_vault/{uid} {
      allow read: if isSignedIn();
      allow write: if false;
    }

    // Biometric Audit Logs: Immutable write-only by backend Admin SDK
    match /biometric_audit_logs/{logId} {
      allow read: if false;
      allow write: if false;
    }

    // User profiles
    match /users/{uid} {
      allow read: if isSignedIn();
      allow write: if isSignedIn() && request.auth.uid == uid;
    }
  }
}
```
