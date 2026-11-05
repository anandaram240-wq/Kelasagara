# MASTER PRODUCTION HANDOVER DIRECTIVE FOR AGENT ARON / ARGON
# Kelasagara Biometric Engine: Zero-Blocker Production Implementation & Release Clearance

**Handover Authority:** Principal Biometric Systems Architect & Application Security Auditor  
**Target Repository:** `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17`  
**Git Branch:** `ui/polish-v1`  
**Base Commit Handover:** `a42994f` (All 13 V15 Audit Reports, Monotonic Threshold Governance, Zero-Conflation Verified)  
**Target Environment:** Flutter 3.47.1, Dart 3.13.1, Node.js v24.14.0, TypeScript 5.9.3, Firebase Admin 13.0, OpenCV SFace ONNX  
**Mission Objective:** Take the remaining 5 operational and cloud blockers identified in the V15 audit from `BLOCKED` to `PASS`, execute the code implementations, run the automated verification suites, and clear the system for **LIVE PRODUCTION CANARY DEPLOYMENT**.

---

## 1. AGENT IDENTITY & ROLE DEFINITION

Act as **Agent Argon**, Principal Biometric Systems Architect, Google Cloud Infrastructure Engineer, Distributed Systems Engineer, Senior Mobile/Flutter Lead, and Production Release Commander.

You are not performing an audit or writing another theoretical assessment. You are taking a mathematically hardened and verified software baseline (where 148 backend tests and 89 Flutter tests already pass 100%) and implementing the physical, distributed, and cloud infrastructure required to achieve complete production readiness.

### Handover Status from V15:
- **RESOLVED & VERIFIED:**
  - Monotonic threshold governance enforced in `backend/src/config.ts` ($\tau_{\text{verify}} = 0.363 < \tau_{\text{dup}} = 0.74 < \tau_{\text{hard}} = 0.90$).
  - Shift re-verification conflation bug in `AccountLifecycleService.reVerifyWorker` fixed and tested.
  - Client vector rejection enforced on all API ingestion schemas (images only).
  - Firestore security rules deny all direct client reads/writes to `biometric_vault`.
  - 13 comprehensive V15 engineering reports compiled in `reports/`.
- **THE 5 REMAINING PRODUCTION BLOCKERS TO CLOSE:**
  1. **Gate G-02 (Critical):** Single-Frame Static JPEG Vulnerability $\to$ Implement Multi-Frame Short Burst Temporal PAD.
  2. **Gate G-04 (High):** Cloud Run In-Memory Gallery Drift $\to$ Implement Native Cloud Firestore Vector Search (KNN/HNSW).
  3. **Gate G-03 (High):** Live Cloud KMS Envelope Encryption $\to$ Implement GCP KMS Live Staging Integration & Health Probes.
  4. **Gate G-05 (Medium):** Live Firestore Rules $\to$ Implement Automated Live Staging Deploy & Penetration Verification Suite.
  5. **Gate G-01 & G-08 (Critical):** Uncalibrated Reference Thresholds & Admin Review $\to$ Implement Biometric Calibration CLI & Operations Review API.

---

## 2. SPRINT 1: MULTI-FRAME SHORT BURST TEMPORAL PAD (GATE G-02)

### The Problem:
Currently, Flutter client blink detection triggers `camera.takePicture()`, transmitting a single static JPEG to `/api/biometrics/verify-1to1`. The backend runs SFace on that 1 static image. An attacker with a virtual camera driver or modified client can bypass client blink checks and replay a static photograph of an authentic worker.

### Implementation Tasks:

#### 1.1 Flutter Multi-Frame Burst Capture (`lib/screens/auth/face_enrollment_screen.dart` & `lib/services/biometric_service.dart`)
- Update the kinematic blink controller so that when a blink cycle is triggered (Eyes Open $\to$ Closed $\to$ Open), the camera captures a rapid 3-frame burst at $\Delta t \approx 100\text{ms}$:
  - `frame1_open.jpg` (Pre-blink baseline: EAR $\ge 0.58$)
  - `frame2_apex.jpg` (Blink apex: EAR $\le 0.28$)
  - `frame3_open.jpg` (Post-blink confirmation: EAR $\ge 0.58$)
- Pack the burst into a JSON payload:
  ```typescript
  interface BiometricBurstPayload {
    burstFramesBase64: [string, string, string]; // Exactly 3 JPEG frames
    clientMetadata: {
      interFrameIntervalMs: number[];
      eulerYaw: number;
      eulerPitch: number;
      deviceTimestamp: string;
    };
  }
  ```

#### 1.2 Backend Multi-Frame Temporal Validator (`backend/src/services/temporal_pad_validator.ts`)
Create a new backend service that validates the 3-frame burst before identity matching:
1. **Photometric Ambient Consistency:**
   - Compute mean luminance ($\mu_L$) and standard deviation ($\sigma_L$) across the 3 frames.
   - Ensure light flux does not experience artificial step-function jumps indicative of screen brightness switching ($|\mu_{L1} - \mu_{L3}| < 15\%$).
2. **Ocular Closure Verification (Temporal Delta):**
   - Run YuNet face detection on all 3 frames.
   - Extract ocular aspect ratio or vertical eye eyelid distance from landmarks.
   - Verify that Frame 2 exhibits significant ocular compression relative to Frame 1 and Frame 3 ($\text{EyeHeight}_2 < 0.6 \times \text{EyeHeight}_1$).
3. **Facial Identity Continuity:**
   - Extract SFace 128-D vectors for Frame 1 ($\vec{u}_1$) and Frame 3 ($\vec{u}_3$).
   - Compute $\text{Sim}(\vec{u}_1, \vec{u}_3) = \vec{u}_1 \cdot \vec{u}_3$.
   - **Assertion:** $\text{Sim}(\vec{u}_1, \vec{u}_3) \ge 0.85$ (Proves the identical physical human head remained continuously in front of the lens during the blink cycle).
4. **Frequency & Texture Analysis:**
   - Run 2D Laplacian variance on the aligned face crop of Frame 1.
   - Enforce $\sigma_{\text{Laplacian}}^2 \in [110, 1500]$ to reject blurry printouts and high-frequency moiré patterns.

#### 1.3 Endpoint Integration
- Update `/api/biometrics/verify-1to1`, `/api/biometrics/enroll-biometric`, and `/api/biometrics/reverify-shift` to route through `TemporalPadValidator.validateBurst(dto)`.
- If temporal validation fails, reject immediately with `status: 'spoof_detected'`, `rejectionReason: 'TEMPORAL_PAD_FAILED'`, without consuming downstream KMS decryption resources.

---

## 3. SPRINT 2: CLOUD FIRESTORE NATIVE VECTOR SEARCH (GATE G-04)

### The Problem:
`InMemoryBiometricIndex` resides in Node.js process heap memory. When Google Cloud Run autoscales to multiple container instances, memory states diverge, allowing simultaneous Sybil enrollments to bypass deduplication.

### Implementation Tasks:

#### 2.1 Native Firestore Vector Search Integration (`backend/src/services/firestore_biometric_repository.ts`)
Replace the single-instance RAM map with Cloud Firestore Vector Search (supported via Firebase Admin SDK):

```typescript
import { FieldValue } from 'firebase-admin/firestore';

export class FirestoreBiometricRepository {
  /**
   * Distributed 1:N Vector Search across all Cloud Run instances.
   * Executes HNSW cosine nearest-neighbor search directly in Cloud Firestore.
   */
  static async findTopKDistributed(
    probeVector: number[],
    excludeUid: string,
    topK: number = 3
  ): Promise<CandidateMatch[]> {
    const vaultRef = admin.firestore().collection('biometric_vault');
    
    // Cloud Firestore Native Vector Search Query
    const vectorQuery = vaultRef.findNearest({
      vectorField: 'embeddingVector',
      queryVector: FieldValue.vector(probeVector),
      limit: topK + 1, // +1 in case the nearest neighbor is the caller's own uid
      distanceMeasure: 'COSINE',
      distanceResultField: 'vectorDistance',
    });

    const snapshot = await vectorQuery.get();
    const candidates: CandidateMatch[] = [];

    for (const doc of snapshot.docs) {
      if (doc.id === excludeUid) continue;
      const data = doc.data();
      const distance = data.vectorDistance as number;
      // Cosine distance d = 1 - cosine_similarity  =>  similarity = 1 - d
      const similarity = 1.0 - distance;

      candidates.push({
        uid: doc.id,
        similarity,
        phoneNumber: data.phoneNumberMasked || '',
      });

      if (candidates.length >= topK) break;
    }

    return candidates;
  }
}
```

#### 2.2 Firestore Vector Index Deployment Configuration (`firestore.indexes.json`)
Add the vector index definition to `firestore.indexes.json`:
```json
{
  "indexes": [],
  "fieldOverrides": [
    {
      "collectionGroup": "biometric_vault",
      "fieldPath": "embeddingVector",
      "indexes": [
        {
          "order": "ASCENDING",
          "queryScope": "COLLECTION"
        },
        {
          "vectorConfig": {
            "dimension": 128,
            "flat": {}
          },
          "queryScope": "COLLECTION"
        }
      ]
    }
  ]
}
```

#### 2.3 Hybrid Caching Layer
Implement an in-memory LRU read-through cache for frequent 1:1 lookups while dispatching all 1:N deduplication queries to Firestore Vector Search, enabling Google Cloud Run to autoscale seamlessly from 1 to 100+ instances without gallery drift.

---

## 4. SPRINT 3: PRODUCTION GOOGLE CLOUD KMS LIVE INTEGRATION (GATE G-03)

### The Problem:
`CloudKmsKeyProvider` throws `KMS_UNAVAILABLE_ERROR (UNVERIFIED-LIVE)` in dev/test because GCP credentials and KMS Keyrings are unset. Live encryption must be provably integrated.

### Implementation Tasks:

#### 3.1 GCP KMS Infrastructure Script (`scripts/deploy_gcp_kms.sh`)
Create an automated Bash script that provisions the staging and production KMS infrastructure:
```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="kelasagara-prod"
LOCATION="asia-south1" # Mumbai data residency for Indian DPDPA compliance
KEYRING_NAME="kelasagara-biometrics"
KEY_NAME="biometric-vault-kek"

echo "[1/4] Enabling Cloud KMS API..."
gcloud services enable cloudkms.googleapis.com --project="$PROJECT_ID"

echo "[2/4] Creating KMS KeyRing..."
gcloud kms keyrings create "$KEYRING_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" || true

echo "[3/4] Creating HSM-backed Key Encryption Key (KEK)..."
gcloud kms keys create "$KEY_NAME" \
  --location="$LOCATION" \
  --keyring="$KEYRING_NAME" \
  --purpose="encryption" \
  --protection-level="hsm" \
  --rotation-period="90d" \
  --next-rotation-time="$(date -u -v+90d +"%Y-%m-%dT00:00:00Z")" \
  --project="$PROJECT_ID" || true

echo "[4/4] Granting IAM permissions to Cloud Run Service Account..."
SERVICE_ACCOUNT="biometric-backend-sa@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud kms keys add-iam-policy-binding "$KEY_NAME" \
  --location="$LOCATION" \
  --keyring="$KEYRING_NAME" \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
  --project="$PROJECT_ID"

echo "KMS Provisioning Complete: projects/${PROJECT_ID}/locations/${LOCATION}/keyrings/${KEYRING_NAME}/cryptoKeys/${KEY_NAME}"
```

#### 3.2 KMS Health Check Probe Endpoint (`/api/biometrics/kms-health`)
In `backend/src/routes/face_routes.ts`, add an authenticated health probe that tests live KMS round-trip latency:
- Generates a synthetic 32-byte test DEK.
- Calls `keyProvider.wrapKey(testDek)` $\to$ records wrap latency.
- Calls `keyProvider.unwrapKey(wrappedDek)` $\to$ records unwrap latency.
- Verifies unwrapped DEK matches original test DEK.
- Returns `{ status: 'healthy', wrapMs: 14, unwrapMs: 12, protectionLevel: 'HSM' }`.

---

## 5. SPRINT 4: LIVE FIRESTORE RULES DEPLOYMENT & PENETRATION SUITE (GATE G-05)

### The Problem:
`firestore.rules` is verified locally in unit tests, but live deployment against the staging Firebase project has not been verified.

### Implementation Tasks:

#### 4.1 Deployment Script (`scripts/deploy_firestore_staging.sh`)
```bash
#!/usr/bin/env bash
set -euo pipefail
echo "Deploying Firestore security rules and vector indexes..."
firebase deploy --only firestore:rules,firestore:indexes --project=kelasagara-staging
```

#### 4.2 Automated Live Penetration Probe (`backend/scripts/verify_live_firestore_security.ts`)
Write an automated Node.js penetration script that initializes a client Firebase Web SDK with a standard worker auth token and attempts:
1. `getDoc(doc(db, 'biometric_vault', 'target_uid'))` $\to$ MUST throw `permission-denied`.
2. `getDocs(query(collection(db, 'biometric_vault')))` $\to$ MUST throw `permission-denied`.
3. `setDoc(doc(db, 'biometric_vault', 'target_uid'), { ... })` $\to$ MUST throw `permission-denied`.
4. `updateDoc(doc(db, 'users', 'worker_uid'), { faceEnrolled: true })` $\to$ MUST throw `permission-denied`.
- The script asserts all 4 attacks return `permission-denied` and outputs an unalterable signed verification report `reports/STAGING_FIRESTORE_SECURITY_VERIFIED.json`.

---

## 6. SPRINT 5: BIOMETRIC CALIBRATION HARNESS & OPERATIONS REVIEW API (G-01 & G-08)

### The Problem:
The threshold `0.363` is the OpenCV reference value. Real field calibration on Indian workers must be conducted, and soft-flagged duplicates ($0.74 \le s < 0.90$) require an administrative human review queue.

### Implementation Tasks:

#### 5.1 Automated Biometric Calibration CLI (`backend/scripts/biometric_calibration_harness.ts`)
Build an automated evaluation runner:
- Ingests a folder containing paired facial images from $N \ge 500$ subjects organized as:
  `/dataset/{subjectId}/condition_A_indoor.jpg`, `condition_B_outdoor.jpg`, etc.
- Extracts SFace 128-D vectors across all images.
- Computes genuine score distribution ($N$ genuine comparisons) and impostor score distribution ($\frac{N(N-1)}{2}$ impostor comparisons).
- Sweeps threshold $\tau \in [0.0, 1.0]$ with $\Delta\tau = 0.001$.
- Calculates empirical FAR, FRR, and F-score at each point.
- Outputs recommended $\tau_{\text{verify}}$ (where $\text{FAR} \le 0.1\%$ and $\text{FRR} \le 3\%$) and recommended $\tau_{\text{dup}}$ (where 1:N false alarm $\le 1\%$).
- Generates JSON summary and ASCII DET curve for audit review.

#### 5.2 Operations Manual Review Queue API (`backend/src/routes/admin_biometric_routes.ts`)
Build endpoints for platform compliance officers:
1. `GET /api/admin/biometrics/duplicate-queue`
   - Returns paginated list of accounts soft-flagged with similarity $0.74 \le s < 0.90$.
   - Includes masked claimant ID, masked matching ID, similarity score, and timestamp.
2. `POST /api/admin/biometrics/review-decision`
   - Payload: `{ reviewId: string, action: 'APPROVE_GENUINE' | 'CONFIRM_FRAUD', officerNotes: string }`.
   - If `APPROVE_GENUINE`: Whitelists the pair, activates worker account, logs `ADMIN_WHITELIST_PAIR` in audit ledger.
   - If `CONFIRM_FRAUD`: Transitions account to `suspended`, triggers cryptographic shredding of the fraudulent template.

---

## 7. FINAL PRODUCTION RELEASE CHECKLIST FOR ARGON

When you have implemented Sprints 1 through 5, execute the following verification commands in sequence:

```bash
# 1. Compile Backend TypeScript (Must be 0 errors)
cd backend && npx tsc --noEmit

# 2. Run Complete Backend Test Suite (All 148+ tests must pass)
npm test

# 3. Run New Temporal PAD & Vector Search Test Suites
npx jest src/tests/temporal_pad_validator.test.ts
npx jest src/tests/firestore_vector_search.test.ts

# 4. Flutter Static Analysis (Must be 0 compile errors)
cd .. && flutter analyze

# 5. Run Flutter Biometric Contract Tests (Must pass 100%)
flutter test test/biometric_contract_test.dart

# 6. Verify Model Assets Checksums
shasum -a 256 backend/assets/models/*
```

### Release Authorization Transition:
Only when all 5 Sprints pass and all tests exit with code `0`, update `backend/src/config.ts`:
```typescript
productionBiometricCalibrationApproved: true,
releaseGateStatus: "PRODUCTION_CANARY_APPROVED"
```

Compile the final handover report into `reports/V16_PRODUCTION_CANARY_AUTHORIZATION.md` and present the verified deployment proof.
