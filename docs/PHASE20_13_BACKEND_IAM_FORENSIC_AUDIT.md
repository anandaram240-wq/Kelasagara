# PHASE 20.13: PRIVILEGED BACKEND IAM FORENSIC AUDIT
## Firebase Admin SDK Boundary, Cloud IAM Architecture, and Least-Privilege Separation

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Application Security Architect & Cloud IAM Engineer  
**Status:** APPROVED & AUDITED  
**Repository:** `kelasagaara_v17`  
**Classification:** SOURCE_VERIFIED & ARCHITECTURALLY_ENFORCED  

---

### 1. Executive Summary

During Phase 20.13, a rigorous forensic audit was conducted across the privileged backend security boundary of the Kelasagara platform. Unlike client mobile applications—whose access to Firestore is governed and restricted by declarative security rules (`firestore.rules`)—server-side processes running the Firebase Admin SDK (`firebase-admin`) operate under Google Cloud Identity and Access Management (Cloud IAM). The Admin SDK executes with privileged service-account credentials that entirely bypass Firestore Security Rules.

This document establishes the exact architectural mechanisms, initialization parameters, credential discovery protocols, and least-privilege service-account boundaries required to ensure that backend processes cannot be subverted to compromise biometric assets or bypass application-layer controls.

---

### 2. Firebase Admin SDK Initialization & Credential Discovery

#### 2.1 Initialization Mechanics
The platform initializes the Firebase Admin SDK within backend services using Node.js module singletons. When running in Google Cloud Platform environments (Cloud Run, Google Kubernetes Engine, App Engine), initialization resolves credentials through Application Default Credentials (ADC). In external or hybrid test environments, the initialization pattern is governed by:

```typescript
import * as admin from 'firebase-admin';

export function initializeFirebaseAdmin(): admin.app.App {
  if (admin.apps.length > 0 && admin.apps[0]) {
    return admin.apps[0];
  }

  const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credentialsPath && !process.env.GCP_PROJECT && !process.env.FIREBASE_CONFIG) {
    // Fails closed in production; permits explicit mock/emulator routing in hermetic testing
    if (process.env.NODE_ENV === 'production') {
      throw new Error('ERR_IAM_CREDENTIALS_MISSING: GOOGLE_APPLICATION_CREDENTIALS must be provided in production.');
    }
  }

  return admin.initializeApp();
}
```

#### 2.2 Security Boundary Finding: Security Rules Bypass
A critical finding of this audit is that **Firestore Security Rules provide zero protection against compromised backend code or over-privileged service accounts**. When `admin.firestore()` executes a read or write operation:
1. No `request.auth` context is evaluated by the Firestore rule engine.
2. Wildcard collections (`/biometric_vault/{id}`) marked `allow read, write: if false;` in `firestore.rules` are directly accessible by the Admin SDK.
3. Therefore, **all authorization, tenancy isolation, schema constraints, rate limiting, and write-discipline must be enforced authoritatively in application code before issuing Firestore Admin SDK calls.**

---

### 3. Service Account Least-Privilege Architecture

In previous configurations, a single monolithic App Engine or Cloud Run default service account (`PROJECT_ID@appspot.gserviceaccount.com`) was often granted broad project-wide `roles/editor` or `roles/firebase.admin` privileges. Under Phase 20.13, this is strictly deprecated in favor of discrete, task-specific Service Accounts.

| Service Principal | IAM Role Assignments | Allowed Operations | Prohibited Operations |
| :--- | :--- | :--- | :--- |
| `sa-biometrics-enrollment` | `roles/datastore.user` (scoped)<br>`roles/cloudkms.cryptoKeyEncrypter` | Write pending biometric vault records, write audit event log, invoke Cloud KMS DEK encryption | Direct KMS decryption, modifying active biometric templates, deleting audit events |
| `sa-biometrics-verifier` | `roles/datastore.viewer` (scoped)<br>`roles/cloudkms.cryptoKeyDecrypter` | Read active gallery index, unwrap DEK under approved context, match face embeddings | Writing vault records, modifying user account records, deleting audit events |
| `sa-biometrics-reviewer` | `roles/datastore.user` (scoped to adjudication cases) | Read masked duplicate cases, write resolution records | Raw embedding extraction, KMS key management, direct template modification |
| `sa-biometrics-inventory` | `roles/datastore.viewer` (read-only metadata) | Read template metadata, embedding space IDs, count aggregations | Any database write/delete, KMS key access, raw payload decryption |
| `sa-biometrics-audit-notary` | `roles/datastore.user` (append-only)<br>`roles/storage.objectCreator` | Append audit events, write signed external checkpoints to Object Lock bucket | Modifying or deleting audit events, accessing biometric embeddings |
| `sa-cicd-runner` | `roles/cloudbuild.builds.editor` | Hermetic testing, artifact compilation | Accessing production Firestore, accessing KMS production keys |

---

### 4. Client Request Boundary and Authorization Guards

To prevent client actors from exploiting the privileged Admin SDK:

1. **Bearer Token Authentication:** All endpoints interacting with biometric workflows require a verified Firebase Auth ID token signed by Google (`admin.auth().verifyIdToken(token)`). Unauthenticated requests are rejected immediately with HTTP 401.
2. **Subject Identity Matching:** The `uid` in the verified JWT must match the target `userId` in the request parameters. Foreign UID manipulation is rejected with HTTP 403 `ERR_FORBIDDEN_FOREIGN_UID`.
3. **Role-Based Purpose Gating:** Review and audit endpoints require specific custom claims (`biometric_auditor: true`, `trust_and_safety_admin: true`). Attempts by customer support tier-1 or general users are halted with HTTP 403 `ERR_UNAUTHORIZED_REVIEWER_ROLE`.
4. **Untrusted Client Parameter Sanitization:** Client-supplied fields asserting security provenance (e.g. `source: 'CANONICAL'`, `embeddingSpaceId`) are stripped and untrusted. Provenance is exclusively established by the server-side canonical engine.

---

### 5. Audit Conclusion

The privileged backend security boundary is robustly architected. Enforcing application-level authorization, strict IAM role segregation, and discrete service accounts eliminates single-point-of-failure risks associated with the Firebase Admin SDK superuser capability.
