# PHASE 20.13: FIRESTORE ADMIN SDK SECURITY BOUNDARY & APPLICATION-LAYER DEFENSE
## Architectural Analysis of Admin SDK Superuser Access vs. Declarative Client Rules

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Application Security Architect  
**Status:** APPROVED & AUDITED  
**Repository:** `kelasagaara_v17`  
**Classification:** SOURCE_VERIFIED & ARCHITECTURALLY_ENFORCED  

---

### 1. The Superuser Nature of Firebase Admin SDK

In Firebase architectures, security models are bifurcated:
1. **Client-Facing Security (`firestore.rules`):** Applies exclusively to calls originating from mobile (Flutter/Android/iOS) and web clients using client SDKs (`firebase/firestore`). These rules evaluate `request.auth`, `resource.data`, and declarative conditions.
2. **Server-Facing Security (Cloud IAM + Admin SDK):** Backend services utilize `@google-cloud/firestore` or `firebase-admin`. **All calls made via the Admin SDK bypass `firestore.rules` completely.**

```
+-------------------------------------------------------------------------------+
|                             CLIENT PERIMETER                                  |
|  [Flutter Android App] ---> (Network / TLS) ---> [Firestore Security Rules]   |
|                                                  |   (Blocks unauthorized)    |
|                                                  v                            |
|                                       [Firestore Database]                    |
|                                                  ^                            |
|                                                  |   (Bypasses Rules)         |
|  [Backend Node.js] -------- (Admin SDK) ---------+                            |
|                             PRIVILEGED PERIMETER                              |
+-------------------------------------------------------------------------------+
```

---

### 2. Failure Mode Analysis: Why Declarative Rules Are Insufficient

If a development team assumes `firestore.rules` protects backend collections, catastrophic security vulnerabilities occur:
- If a client routes an untrusted request to a backend endpoint (e.g. `POST /api/biometrics/enroll`), and the backend executes `admin.firestore().collection('biometric_vault').doc(id).set(payload)` without verifying caller ownership, an attacker can overwrite any biometric profile.
- A client-side rule `allow write: if false;` on `/biometric_vault/{id}` does not halt the Admin SDK call.
- A field-level validation rule `request.resource.data.keys().hasOnly(...)` does not restrict the Admin SDK.

---

### 3. Application-Layer Guard Architecture

Under Phase 20.13, every backend service interacting with Firestore implements strict defense-in-depth guards:

#### 3.1 Strict Caller Verification (`verifyCallerAuthorization`)
Before interacting with any database collection, the backend verifies caller credentials:
```typescript
export async function verifyCallerAuthorization(
  authHeader: string | undefined,
  targetUid: string
): Promise<{ callerUid: string; claims: Record<string, any> }> {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('ERR_UNAUTHENTICATED: Bearer token is required.');
  }

  const token = authHeader.substring(7);
  const decodedToken = await admin.auth().verifyIdToken(token);

  if (decodedToken.uid !== targetUid) {
    throw new Error('ERR_FORBIDDEN_FOREIGN_UID: Caller UID does not match target profile UID.');
  }

  return { callerUid: decodedToken.uid, claims: decodedToken };
}
```

#### 3.2 Schema Whitelisting and Sanitization
The backend guarantees that client-injected provenance flags (e.g. `canonical: true`, `verified: true`, `source: 'CANONICAL'`) are discarded. The database payload is constructed exclusively using server-generated values:
```typescript
const vaultRecord = {
  templateId: generateSecureTemplateId(),
  userId: verifiedCaller.callerUid,
  embeddingSpaceId: CURRENT_CANONICAL_EMBEDDING_SPACE_ID,
  modelIdentifier: YUNET_SFACE_CANONICAL_V3.sfaceIdentifier,
  classification: 'CANONICAL_SFACE_YUNET_112_V2',
  status: 'ACTIVE',
  encryptedDek: envelope.encryptedDek,
  ciphertext: envelope.ciphertext,
  iv: envelope.iv,
  authTag: envelope.authTag,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
};
```

#### 3.3 Transaction Boundary Enforcement
Database mutations adhere to atomic read-before-write transactions to prevent concurrency anomalies and race conditions. All cryptographic operations and heavy ONNX inferences are performed outside the transaction closure.

---

### 4. Summary & Verification

The test suite `src/tests/phase20_13_privileged_backend_security.test.ts` (Tests 1–10) explicitly exercises these boundaries:
- Test 1 verifies that untrusted client requests cannot access the vault.
- Test 2 proves that client-forged provenance flags are quarantined as `LEGACY_TEMPLATE_UNKNOWN`.
- Test 3 verifies foreign UID access rejection.
- Test 4 verifies token enforcement.

The Firestore Admin SDK security boundary is fully safeguarded at the application layer.
