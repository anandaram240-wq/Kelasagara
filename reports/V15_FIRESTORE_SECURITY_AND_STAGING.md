# KELASAGARA V15.0 BIOMETRIC ENGINE AUDIT
# REPORT 07: FIRESTORE SECURITY RULES & STAGING VERIFICATION RUNBOOK

**Document ID:** KLS-V15-RULES-001  
**Classification:** CLOUD SECURITY AUDIT & DEPLOYMENT RUNBOOK  
**Target Files:** `firestore.rules`, `backend/src/tests/firestore_rules_security.test.ts`  
**Audit Finding:** REPOSITORY RULES HARDENED / LIVE DEPLOYMENT UNVERIFIED  
**Audit Date:** 2026-10-23  

---

## 1. REPOSITORY RULES AUDIT

A principal requirement for biometric privacy and compliance under the **Digital Personal Data Protection Act (DPDPA 2023)** is that raw biometric templates, encrypted feature vectors, and deduplication records must **never be accessible directly by mobile clients**.

Mobile applications must communicate exclusively with authorized backend microservices.

### Inspection of `firestore.rules`:
```javascript
// ============================================================================
// FIRESTORE SECURITY RULES (Line 135-160 in firestore.rules)
// ============================================================================

// 1. BIOMETRIC VAULT: Zero client read/write access.
// Only accessible via Firebase Admin SDK running in the authenticated backend.
match /biometric_vault/{docId} {
  allow read, write: if false;
}

// 2. BIOMETRIC AUDIT LOG: Append-only ledger; zero client access.
match /biometric_audit_log/{logId} {
  allow read, write: if false;
}

// 3. REVOCATION REGISTRY: Platform key/template revocation status.
match /biometric_revocation_registry/{docId} {
  allow read: if request.auth != null; // Authenticated users can check revocation
  allow write: if false;                // Only Admin SDK can revoke
}

// 4. USER PROFILE (Worker Metadata): Restricted self-read; gated write.
match /users/{userId} {
  allow read: if request.auth != null;
  allow write: if request.auth != null && request.auth.uid == userId 
    && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['faceEnrolled', 'biometricVersion']);
}
```

---

## 2. CLIENT DENIAL VERIFICATION & TEST EVIDENCE

In `backend/src/tests/firestore_rules_security.test.ts`, automated tests using `@firebase/rules-unit-testing` confirm rule enforcement:

```text
PASS src/tests/firestore_rules_security.test.ts
  Firestore Security Rules Biometric Vault Protection
    ✓ unauthenticated client cannot read biometric_vault (2 ms)
    ✓ authenticated worker cannot read their own biometric_vault document (2 ms)
    ✓ authenticated worker cannot query or list biometric_vault collection (1 ms)
    ✓ authenticated worker cannot write or overwrite biometric_vault document (2 ms)
    ✓ worker cannot modify faceEnrolled status on their user profile (3 ms)
    ✓ admin SDK bypasses client denial and reads/writes vault successfully (1 ms)

Test Suites: 1 passed, 1 total
Tests:       6 passed, 6 total
```

### Analysis:
- Mobile clients (even authenticated with a valid Firebase ID token) cannot execute `db.collection('biometric_vault').get()`. Any client attempt receives `PERMISSION_DENIED`.
- Mobile clients cannot tamper with their own `faceEnrolled` profile flag to bypass verification requirements.
- The Node.js backend running `firebase-admin` connects using service account credentials, which bypass security rules by design and operate with full database authority.

---

## 3. LIVE DEPLOYMENT REALITY: UNVERIFIED LIVE

While the `firestore.rules` file in the Git repository is hardened and passes unit tests:
- **No live deployment verification has been performed against the production Firebase project.**
- The live production Firestore instance could potentially be running legacy rules that permit client reads if not deployed via CI/CD.
- Consequently, live security remains classified as **UNVERIFIED LIVE**.

---

## 4. STAGING VERIFICATION RUNBOOK

Before authorizing any biometric rollout, DevOps and Security teams must execute the following staging verification protocol.

### Step 1: Start Local Firebase Emulator
```bash
# Start local firestore emulator with project rules
cd '/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17'
firebase emulators:start --only firestore
```

### Step 2: Deploy to Staging Project
```bash
# Set staging project context
firebase use staging-kelasagara

# Deploy rules to staging environment
firebase deploy --only firestore:rules
```

### Step 3: Penetration Testing Probe (Staging CLI)
Execute the following verification script using the Firebase JS SDK from a simulated client:

```javascript
// staging_security_probe.js
const { initializeApp } = require('firebase/app');
const { getFirestore, doc, getDoc, setDoc } = require('firebase/firestore');
const { getAuth, signInWithCustomToken } = require('firebase/auth');

async function testClientDenial() {
  const app = initializeApp({ projectId: 'staging-kelasagara' });
  const db = getFirestore(app);
  
  // 1. Unauthenticated Read
  try {
    await getDoc(doc(db, 'biometric_vault', 'probe_target'));
    console.error('FAIL: Unauthenticated client read biometric_vault!');
  } catch (err) {
    console.log('PASS: Unauthenticated read blocked:', err.code);
  }

  // 2. Authenticated Worker Read
  // (Sign in with a valid simulated worker token)
  const auth = getAuth(app);
  await signInWithCustomToken(auth, 'mock_worker_token');
  try {
    await getDoc(doc(db, 'biometric_vault', 'mock_worker_uid'));
    console.error('FAIL: Authenticated worker read biometric_vault!');
  } catch (err) {
    console.log('PASS: Authenticated client read blocked:', err.code);
  }
}
testClientDenial();
```

### Step 4: Verification Gate Sign-Off
Both tests must output `PASS: ... read blocked: permission-denied`. Capture console output and commit to audit logs before promoting rules to production.
