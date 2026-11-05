# KELASAGARA BIOMETRIC ENGINE V8.0
# Complete Biometric System Architecture Specification
## Dual-Layer Edge/Cloud Architecture, Trust Boundaries, KMS Cryptographic Storage, In-Memory 1:N Indexing, and DPDPA Data Contracts

**Document ID:** `DOC-ARCH-V8-01`  
**System:** Kelasagara Biometric Platform  
**Target Environments:** Flutter / Android Client, Cloud Run Node/TypeScript Backend, Google Cloud KMS, Cloud Firestore  
**Classification:** Enterprise System Architecture Specification  
**Version:** 8.0.0-PROD  
**Date:** 2026-10-22  

---

## 1. Architectural Overview & System Design Principles

The Kelasagara Biometric Engine V8.0 implements an enterprise-grade, privacy-first identity architecture designed for informal and gig-economy labor markets across India. The architecture separates edge device processing from cloud-authoritative deduplication, balancing low-latency on-device user feedback with cryptographic tamper-resistance and strict statutory data protection.

```
+====================================================================================================+
|                                    KELASAGARA BIOMETRIC V8.0 HIGH-LEVEL FLOW                       |
+====================================================================================================+
                                                                                                      
  [Worker / Applicant Phone]                                 [Trusted Cloud Infrastructure]          
  +-------------------------------------+                    +-------------------------------------+  
  | 1. Camera Capture (YUV_420_888)     |                    | 9. API Gateway & Rate Limiting      |  
  | 2. ISO 39794-5 Quality & Pose Gate  |                    | 10. Challenge Nonce Single-Use Check |  
  | 3. 513-Pt Dense Mesh Extraction     |                    | 11. InMemoryBiometricIndex 1:N Scan |  
  | 4. ISO 30107-3 Kinematic Blink PAD  |                    |     - Cosine Sim >= 0.74 Intercept  |  
  | 5. C++ 2D Laplacian Variance (σ²L)  | --(TLS 1.3 POST)-->| 12. DPDPA PII Masking Output        |  
  | 6. Whitened RFF Embedding (128-D)   |                    | 13. GCP KMS Envelope Encryption     |  
  | 7. HMAC-SHA256 WADH Signature       |                    | 14. Atomic Write: biometric_vault   |  
  | 8. Zero-Out Raw Frame in RAM        |                    +-------------------------------------+  
  +-------------------------------------+                                                             
```

### Core Architectural Invariants
1. **Zero Client Biometric Authority:** Client mobile devices are untrusted. The client can propose identity claims and extract local quality metrics, but all authoritative registration approvals and duplicate identity determinations are executed exclusively by the backend service.
2. **Zero Template Exposure:** Client applications never receive, query, or enumerate stored biometric templates of other users. 1:N searches execute entirely inside server RAM.
3. **Multi-Modal Separation:** Dense facial geometry ($\ge 500$ points), neural recognition embeddings ($\mathbb{S}^{127}$), and presentation attack detection (PAD) operate as distinct components with independent API contracts.
4. **Envelope Encryption at Rest:** Biometric templates stored in Firestore are sealed with AES-256-GCM using Google Cloud KMS envelope encryption with canonical length-prefixed AAD context binding.
5. **Fail-Closed Availability Posture:** Network timeouts, service interruptions, or cryptographic verification failures immediately transition the client to a fail-closed state. No worker account is activated without an explicit server-signed approval.

---

## 2. Component Taxonomy & Trust Boundaries

The system is partitioned into three formal cryptographic trust domains:

```
+----------------------------------------------------------------------------------------------------+
| DOMAIN 1: UNTRUSTED CLIENT DOMAIN (Android Mobile App)                                             |
|                                                                                                    |
|  - CameraX Driver (Hardware Camera HAL)                                                            |
|  - Google ML Kit FaceDetector (enableLandmarks: true, enableContours: true)                        |
|  - AdvancedLandmarkAnalyzer (ISO 39794-5 Quality Gate: IPD >= 90px, |Yaw| <= 5°)                   |
|  - DenseFacialMarkerEngine (513 Canonical 3D Anatomical Vertices)                                  |
|  - Iso30107PadController (Active Kinematic Blink State Machine)                                    |
|  - Native C++ Shared Library (libbiometric_engine.so / 2D Laplacian σ²L Kernel)                    |
|  - LandmarkEmbedding (kelasagara_biomatch_v3_whitened / Rahimi-Recht RFF onto S¹²⁷)                |
|  - Volatile Memory Scrubber (DPDPA 2023 Explicit Zero-Out of Raw Pixel & Vector Buffers)           |
+----------------------------------------------------------------------------------------------------+
                                                  |
                     === BOUNDARY 1: Mutual TLS 1.3 / Certificate Pinning ===
                                                  |
                                                  v
+----------------------------------------------------------------------------------------------------+
| DOMAIN 2: TRUSTED APPLICATION DOMAIN (Cloud Run Node/TypeScript Backend)                          |
|                                                                                                    |
|  - Express.js API Router (/api/biometrics/*)                                                       |
|  - IP-Enforced Token Bucket Rate Limiter (60 requests / minute)                                    |
|  - Firebase Auth Admin SDK (Cryptographic JWT Token Verification)                                  |
|  - Challenge Nonce Manager (Single-Use Nonce Store with 300s TTL)                                  |
|  - FaceInference Service (SFace OpenCV Zoo ONNX Runtime Worker)                                    |
|  - InMemoryBiometricIndex (Thread-Safe 1:N Linear Vector Search Index in RAM)                      |
|  - Duplicate Decision Engine (Decision Thresholds: τ_verify = 0.38, τ_dedup = 0.74, τ_block = 0.90)|
|  - DPDPA PII Masking Engine (KLS-xK9***wXy-7890 Display Masking)                                   |
|  - Immutable Audit Service (Structured Event Logging)                                              |
+----------------------------------------------------------------------------------------------------+
                                                  |
                     === BOUNDARY 2: Cloud IAM Role-Based Access Control ===
                                                  |
                                                  v
+----------------------------------------------------------------------------------------------------+
| DOMAIN 3: SECURE DATA & KEY MANAGEMENT DOMAIN (GCP KMS & Cloud Firestore)                         |
|                                                                                                    |
|  - Google Cloud Key Management Service (Cloud KMS HSM-Backed Key Ring)                             |
|    * Asymmetric / Symmetric Key Encryption Key (KEK)                                               |
|    * Dynamic Data Encryption Key (DEK) Wrapping / Unwrapping                                       |
|  - Cloud KMS Envelope Encryption Engine (AES-256-GCM / 96-bit Unique IV / 128-bit Auth Tag)        |
|  - Length-Prefixed Binary AAD Context Formatter (tenantId + uid + modelVersion)                     |
|  - Cloud Firestore: biometric_vault/{uid} Collection (Locked by Security Rules to Admin SDK Only)  |
|  - Cloud Firestore: audit_events Collection (Append-Only Event Ledger)                             |
+----------------------------------------------------------------------------------------------------+
```

---

## 3. End-to-End Processing Pipelines

### 3.1 Edge Client Capture & Feature Pipeline
1. **Frame Ingestion:** CameraX delivers `YUV_420_888` camera frames at 30 fps via an image analysis use-case.
2. **Quality Gating (`AdvancedLandmarkAnalyzer`):**
   - Interpupillary Distance (IPD): $\text{IPD} = \sqrt{(X_R - X_L)^2 + (Y_R - Y_L)^2} \ge 90.0\text{ px}$.
   - Geometric Yaw: $|Yaw| = \left|\frac{X_{\text{nose}} - X_{\text{mid}}}{\text{IPD}} \times 30.0^\circ\right| \le 5.0^\circ$.
   - Geometric Pitch: $|Pitch| \le 5.0^\circ$; Roll: $|Roll| \le 8.0^\circ$.
   - Frames violating these criteria are rejected instantly with real-time on-screen guidance.
3. **Dense Geometry Generation (`DenseFacialMarkerEngine`):**
   - Assembles **513 canonical 3D vertices** across 11 facial anatomical manifolds.
4. **Kinematic Presentation Attack Detection (`Iso30107PadController`):**
   - Monitors eye-opening probability across frames.
   - Detects physiological blink: Open ($\ge 0.58$) $\to$ Closed ($\le 0.28$) $\to$ Recovery ($\ge 0.58$).
   - Computes 2D Laplacian variance $\sigma^2_L$ over the face crop. Bona fide live face: $\sigma^2_L \in [110, 1850]$.
5. **Feature Whitening & Embedding (`LandmarkEmbedding`):**
   - Computes 30 scale-invariant anthropometric spatial ratios $\mathbf{z} \in \mathbb{R}^{30}$.
   - Applies Rahimi-Recht Random Fourier Features with bandwidth $\sigma = 4.2$:
     $$\mathbf{e} = \frac{1}{\sqrt{64}} \left[ \cos(\mathbf{\Omega} \mathbf{z}), \; \sin(\mathbf{\Omega} \mathbf{z}) \right]^T \in \mathbb{S}^{127}$$
   - Unit L2 norm is analytically invariant: $\|\mathbf{e}\|_2 \equiv 1.0000000$.
6. **DPDPA Volatile Memory Scrub:**
   - Raw pixel arrays and intermediate unnormalized landmark buffers are immediately zeroed via `nativeResult.embedding.fillRange(0, length, 0.0)`.

### 3.2 Cloud Deduplication & Enrollment Pipeline
1. **Authentication & Rate Limiting:** Verifies Firebase Auth JWT; asserts client IP does not exceed 60 req/min.
2. **Challenge Verification:** Validates server-issued cryptographic nonce against Redis/Memory store. If expired or already consumed, returns HTTP 403 `CHALLENGE_EXPIRED`.
3. **1:N Memory Index Scan (`InMemoryBiometricIndex`):**
   - Compares probe vector $\mathbf{e}_{\text{probe}}$ against all $N$ registered templates using vectorized dot product.
   - Identifies top candidate: $s_{\max} = \max_{j \ne \text{caller}} (\mathbf{e}_{\text{probe}} \cdot \mathbf{g}_j)$.
4. **Decision Logic:**
   - If $s_{\max} \ge 0.90$: **Hard Duplicate Block** (`CROSS_ACCOUNT_HARD_BLOCK`).
   - If $s_{\max} \ge 0.74$: **Duplicate Account Detected** (`DUPLICATE_FOUND`). Returns masked identifier `KLS-xK9***wXy-7890` and instructions to recover the original profile.
   - If $s_{\max} < 0.74$: **Approval Granted**.
5. **KMS Envelope Encryption (`v3_kms_gcm`):**
   - Generates ephemeral 256-bit DEK.
   - Encrypts embedding array using AES-256-GCM with a random 96-bit IV.
   - Encrypts DEK using Google Cloud KMS Key Encryption Key (KEK).
   - Constructs binary length-prefixed AAD context:
     $$\text{AAD} = \text{len}(\text{tenantId}) \,\|\, \text{tenantId} \,\|\, \text{len}(uid) \,\|\, uid \,\|\, \text{len}(modelVersion) \,\|\, modelVersion$$
6. **Atomic Storage & Index Insertion:**
   - Writes sealed envelope to `biometric_vault/{uid}`.
   - Atomically updates `InMemoryBiometricIndex` in RAM.
   - Updates user profile: `biometricEnrolled: true`, `biometricVerified: true`.

---

## 4. Stored Data Architecture & Security Schema

### 4.1 Firestore Document Schema (`biometric_vault/{uid}`)

```typescript
interface BiometricVaultDocument {
  // Sealed Biometric Payload (Envelope Encrypted)
  encryptedVector: string;       // Base64-encoded AES-256-GCM ciphertext
  iv: string;                    // Base64-encoded 96-bit initialization vector
  authTag: string;               // Base64-encoded 128-bit GCM authentication tag
  wrappedDek: string;            // Base64-encoded KMS-wrapped Data Encryption Key
  
  // Cryptographic Context Binding
  envelopeVersion: "v3_kms_gcm"; // Strict envelope version tag
  aadContext: {
    tenantId: string;            // "kelasagara_production"
    uid: string;                 // User Firebase UID
    modelVersion: string;        // "kelasagara_biomatch_v3_whitened"
  };
  
  // Model & Processing Contract Metadata
  modelVersion: string;          // "kelasagara_biomatch_v3_whitened"
  preprocessingVersion: string;  // "rff_whitened_sigma_4_2"
  embeddingDimension: 128;       // Exactly 128 float values
  normalization: "L2_HYPERSPHERE"; // ||z|| = 1.0
  
  // Quality & Verification Audit Trail
  qualityMetrics: {
    ipdPixels: number;           // e.g. 104.2 (>= 90 px)
    laplacianVariance: number;   // e.g. 342.5 (110 - 1850)
    blinkVerified: boolean;      // true
    landmarkCount: number;       // 513
  };
  
  // Masked Metadata for Safe Recovery
  phoneNumberMasked: string;     // "+91 ******7890"
  displayNameMasked: string;     // "Ra*** K***"
  
  // Timestamps & Lifecycle
  enrolledAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
  schemaVersion: 3;
}
```

### 4.2 Firestore Security Rules Lockdown (`firestore.rules`)
```javascript
// Strict locking of biometric vault collection
match /biometric_vault/{userId} {
  // Direct client read is strictly forbidden (zero template harvesting)
  allow read: if false;
  
  // Direct client write is strictly forbidden (zero client forgery)
  allow write: if false;
}
```
*Note:* The trusted backend service accesses `biometric_vault` via the **Firebase Admin SDK**, which bypasses security rules using Cloud IAM service account credentials.

---

## 5. Formal API Specification & Data Contracts

### 5.1 Request Cryptographic Challenge Nonce
**`POST /api/biometrics/challenge`**
- **Authentication:** `Authorization: Bearer <Firebase_ID_Token>`
- **Request Body:**
  ```json
  { "action": "enroll" | "verify" | "cross_check" }
  ```
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "status": "challenge_issued",
    "data": {
      "nonce": "chal_9f83a2c019d84e5b",
      "expiresAt": 1792683000000,
      "ttlMs": 300000
    },
    "serverTimestamp": "2026-10-22T21:30:00.000Z"
  }
  ```

### 5.2 Biometric Enrollment & Deduplication
**`POST /api/biometrics/enroll`**
- **Authentication:** `Authorization: Bearer <Firebase_ID_Token>`
- **Request Body:**
  ```json
  {
    "probeVector": [0.0821, -0.0412, ..., 0.0531], // 128 floats (||v|| = 1.0)
    "nonce": "chal_9f83a2c019d84e5b",
    "requestHash": "7f8b9c...a31", // HMAC-SHA256 WADH digest
    "qualityReport": {
      "ipdPixels": 102.4,
      "laplacianVariance": 310.2,
      "blinkDetected": true,
      "landmarkCount": 513
    }
  }
  ```
- **Response — Approved Case (200 OK):**
  ```json
  {
    "success": true,
    "status": "approved",
    "data": {
      "isApproved": true,
      "isDuplicate": false,
      "enrolledAt": "2026-10-22T21:30:01.000Z",
      "modelVersion": "kelasagara_biomatch_v3_whitened"
    },
    "serverTimestamp": "2026-10-22T21:30:01.000Z"
  }
  ```
- **Response — Duplicate Intercepted (409 Conflict):**
  ```json
  {
    "success": false,
    "status": "duplicate",
    "error": {
      "code": "BIOMETRIC_DUPLICATE_DETECTED",
      "message": "This face is already registered under an existing account."
    },
    "data": {
      "isDuplicate": true,
      "isHardBlock": false,
      "maskedUserId": "KLS-xK9***wXy-7890",
      "maskedPhone": "+91 ******7890",
      "maskedName": "Ra*** K***",
      "similarityPercent": 88
    },
    "serverTimestamp": "2026-10-22T21:30:01.000Z"
  }
  ```

### 5.3 Cross-Account Login Deduplication Check
**`POST /api/biometrics/cross-account-check`**
- **Authentication:** `Authorization: Bearer <Firebase_ID_Token>`
- **Request Body:**
  ```json
  {
    "embeddingBase64": "vPz8Pj..." // Base64-encoded Float32Array (128 floats)
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "status": "no_match" | "duplicate" | "hard_block",
    "data": {
      "isDuplicate": false,
      "isHardBlock": false,
      "topSimilarity": 0.28,
      "similarityPercent": 28
    },
    "serverTimestamp": "2026-10-22T21:30:02.000Z"
  }
  ```

### 5.4 Database Readiness & Availability Probe
**`GET /api/biometrics/db-readiness`**
- **Authentication:** `Authorization: Bearer <Firebase_ID_Token>`
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "status": "db_ready",
    "data": {
      "firestoreLatencyMs": 42,
      "enrolledTemplates": 1420,
      "ramIndexSize": 1420,
      "isRamIndexWarm": true,
      "modelVersion": "kelasagara_biomatch_v3_whitened",
      "preprocessVersion": "rff_whitened_sigma_4_2",
      "requesterEnrolled": true,
      "systemAvailability": {
        "firestoreOk": true,
        "ramIndexOk": true,
        "deduplicationReady": true
      }
    },
    "serverTimestamp": "2026-10-22T21:30:03.000Z"
  }
  ```

---

## 6. Large-Scale In-Memory 1:N Index Architecture

To eliminate Firestore query latency and avoid downloading massive collections during 1:N deduplication, the backend runs **`InMemoryBiometricIndex`**:

```
+====================================================================================================+
|                                  InMemoryBiometricIndex MEMORY LAYOUT                              |
+====================================================================================================+
                                                                                                      
  Float32Array Matrix (Flat Contiguous Buffer in RAM):                                                
  +-------------------------------------------------------------------------------------------------+ 
  | User 0 (128 floats) | User 1 (128 floats) | ... | User N-1 (128 floats)                          | 
  +-------------------------------------------------------------------------------------------------+ 
  Size: N × 128 × 4 bytes  (At N = 50,000 workers: exactly 25.6 MB RAM)                               
                                                                                                      
  Metadata Registry (Parallel Array):                                                                 
  +-------------------------------------------------------------------------------------------------+ 
  | [0] -> { uid: "usr_001", phoneMasked: "+91 ***1234", nameMasked: "Ra***" }                     | 
  | [1] -> { uid: "usr_002", phoneMasked: "+91 ***5678", nameMasked: "Su***" }                     | 
  +-------------------------------------------------------------------------------------------------+ 
```

### 6.1 Server Startup Warm-Up Sequence (`warmUpBiometricIndex`)
When the Cloud Run container boots:
1. `warmUpBiometricIndex()` queries all records in `biometric_vault`.
2. Each document's encrypted payload is unwrapped and decrypted via KMS.
3. Decrypted 128-D float vectors are loaded into the contiguous `Float32Array` matrix.
4. The warm-up process completes before the Express HTTP server accepts traffic, ensuring zero cold-start delay during user onboarding.

### 6.2 Mutation Safety & Thread Consistency
- **New Enrollments:** Appended atomically to both Firestore and `InMemoryBiometricIndex` within a mutex lock.
- **Account Deletions (DPDPA Right to Erasure):** The entry is zeroed in the memory matrix and removed from the metadata map; the Firestore vault document is permanently deleted.

---

## 7. Cryptographic Envelope & Key Lifecycle Management

```
+----------------------------------------------------------------------------------------------------+
|                                    CLOUD KMS ENVELOPE ENCRYPTION FLOW                              |
+----------------------------------------------------------------------------------------------------+
                                                                                                      
  1. Plaintext Embedding (128 floats / 512 bytes)                                                     
  2. Ephemeral DEK Generation: crypto.randomBytes(32) -> 256-bit Key                                  
  3. KMS Encrypt Call: kms.encrypt(KEK_NAME, DEK) -> wrappedDek (Base64)                              
  4. Nonce Generation: crypto.randomBytes(12) -> 96-bit IV                                            
  5. AAD Binary Serialization: Length-Prefixed Canonical Buffer                                       
  6. AES-256-GCM Encrypt:                                                                             
     Ciphertext, AuthTag = AES_GCM_Encrypt(Plaintext, DEK, IV, AAD)                                   
  7. Secure Wipe: DEK explicitly overwritten in memory with crypto.randomBytes(32)                    
```

- **Master Key Encryption Key (KEK):** Stored inside Google Cloud KMS HSM (FIPS 140-2 Level 3 certified). KEK never leaves the KMS boundary.
- **Key Rotation Policy:** KMS master keys rotate automatically every 90 days. Existing encrypted templates remain decryptable via versioned key URIs (`projects/.../cryptoKeyVersions/1`).
- **Downgrade Attack Resistance:** Decryption routines inspect `envelopeVersion`. If `minEnvelopeVersion` is configured to `v3_kms_gcm`, any legacy v1/v2 unauthenticated payload is rejected immediately (`DOWNGRADE_ATTACK_INTERCEPTED`).
