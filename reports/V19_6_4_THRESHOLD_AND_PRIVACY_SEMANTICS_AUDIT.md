# KELASAGARA BIOMATCH V19.6.4: THRESHOLD SEMANTICS & PRIVACY CLAIMS AUDIT
**Document ID:** `KB-V19-6-4-REP-03`  
**Classification:** Biometric Matching Semantics, Cryptographic Integrity & Privacy Architecture Audit  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Biometric Calibration Approved:** `false`  
**Target Architecture:** Node.js Backend & Flutter Mobile Client  
**Evaluation Date:** October 24, 2026

---

## 1. SFACE THRESHOLD SEMANTICS AUDIT: SIMILARITY VS DISTANCE

### 1.1 The Mathematical Definitions
For two 128-dimensional L2-normalized feature vectors $\mathbf{u}, \mathbf{v} \in \mathbb{R}^{128}$ on the unit hypersphere ($\|\mathbf{u}\|_2 = \|\mathbf{v}\|_2 = 1.0$):

1. **Cosine Similarity ($S_{\text{cos}}$):**
   $$S_{\text{cos}}(\mathbf{u}, \mathbf{v}) = \frac{\mathbf{u} \cdot \mathbf{v}}{\|\mathbf{u}\|_2 \|\mathbf{v}\|_2} = \sum_{i=1}^{128} u_i v_i \in [-1.0, +1.0]$$
   - $\mathbf{u} = \mathbf{v} \implies S_{\text{cos}} = +1.0$ (Identical).
   - $\mathbf{u} \perp \mathbf{v} \implies S_{\text{cos}} = 0.0$ (Orthogonal).
   - Higher score $\implies$ Greater similarity.

2. **Cosine Distance ($D_{\text{cos}}$):**
   $$D_{\text{cos}}(\mathbf{u}, \mathbf{v}) = 1.0 - S_{\text{cos}}(\mathbf{u}, \mathbf{v}) \in [0.0, 2.0]$$
   - $\mathbf{u} = \mathbf{v} \implies D_{\text{cos}} = 0.0$.
   - Lower score $\implies$ Greater similarity.

3. **Euclidean / L2 Distance ($D_{\text{L2}}$):**
   $$D_{\text{L2}}(\mathbf{u}, \mathbf{v}) = \|\mathbf{u} - \mathbf{v}\|_2 = \sqrt{2(1.0 - S_{\text{cos}})}$$

---

### 1.2 Code Inspection & Ground Truth

We inspected the actual implementation across the codebase:
- In [`backend/src/services/biometric_matching.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/biometric_matching.ts):
  ```typescript
  export function evaluateVerification(similarity: number, threshold = config.verificationThreshold) {
    return {
      isMatch: similarity >= threshold,
      similarity,
      threshold,
    };
  }

  export function evaluateMatch(maxSimilarity: number) {
    if (maxSimilarity >= hardBlockThresh) return { decision: "duplicate", isHardBlock: true };
    if (maxSimilarity >= config.duplicateThreshold) return { decision: "duplicate", isHardBlock: false };
    if (maxSimilarity >= config.ambiguityThreshold) return { decision: "ambiguity", isHardBlock: false };
    return { decision: "unique", isHardBlock: false };
  }
  ```
- In [`lib/services/biometric_service.dart`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/services/biometric_service.dart):
  ```dart
  final sim = (data['similarity'] as num?)?.toDouble() ?? 0.0;
  final th = (data['threshold'] as num?)?.toDouble() ?? 0.363;
  if (statusCode == 200 && success && (statusStr == 'verified' || statusStr == 'enrolled')) ...
  ```

### 1.3 Scientific Audit Finding
1. **The Implementation is Correct and Consistent:**
   - The code strictly computes **Cosine Similarity** ($\mathbf{u} \cdot \mathbf{v}$).
   - Decisions evaluate `score >= threshold`.
   - A genuine pair with similarity $0.50$ is **ACCEPTED** ($0.50 \ge 0.363$).
   - An impostor pair with similarity $0.20$ is **REJECTED** ($0.20 < 0.363$).
2. **Prior Report Documentation Defect:**
   - In prior audit reports (V19.6.1, V19.6.2, V19.6.3), the thresholds were mistakenly labeled as:
     `verificationThreshold = 0.363 (cosine distance)`
     `duplicateThreshold = 0.740 (cosine distance)`
     `hardBlockThreshold = 0.900 (cosine distance)`
   - This was an **inverted terminology error in documentation**. If these thresholds had been evaluated as cosine distance, a score of $0.50$ would have been rejected for being greater than $0.363$.
3. **OpenCV Zoo SFace Calibration Warning:**
   - OpenCV's published benchmark lists $\tau = 0.363$ as the cosine similarity threshold corresponding to $\text{FAR} \approx 0.1\%$ on general benchmark splits (LFW / IJB-C).
   - This threshold has **NOT been empirically calibrated on rural Indian demographic field data** (Gate G-01 remains active). In field lighting (kerosene lamps, direct sun, monsoon overcast) and across deep skin tones (Monk Skin Tone 7–10), genuine similarity distributions may shift significantly.

---

## 2. SCIENTIFIC AUDIT OF PRIVACY CLAIMS

### 2.1 Claim 1: "Zero Raw-Image Persistence"
- **Status:** `VERIFIED AT DATABASE LAYER` | `QUALIFIED AT RUNTIME RUNNER`.
- **Reality:**
  - Neither `face_routes.ts` nor `biometric_enrollment.ts` writes raw JPEG bytes or base64 strings to Firestore, Cloud Storage, or local disk files.
  - However, in Node.js, `express.json({ limit: "15mb" })` receives and parses base64 payloads into V8 strings in memory.
  - V8 heap allocation does not guarantee immediate zeroing or overwriting of freed memory pages. Until V8 garbage collection occurs, memory buffers containing image base64 data exist in process RAM.
  - No secure memory wiping (`Buffer.fill(0)`) is executed on parsed string primitives (which are immutable in JavaScript).

### 2.2 Claim 2: "Immediate Garbage Collection of JPEG Buffers"
- **Status:** `UNVERIFIED` / `ARCHITECTURALLY INACCURATE`.
- **Reality:**
  - JavaScript provides no API for deterministic immediate memory deallocation. Dereferencing variables (`buffer = null`) merely marks memory as eligible for garbage collection.
  - V8 runs generational garbage collection asynchronously based on heap pressure.
  - Claiming "immediate garbage collection" in formal security documentation is technically incorrect; it must be described as **ephemeral in-memory processing without explicit disk persistence**.

### 2.3 Claim 3: "AES-256-GCM Encryption of Biometric Templates via Cloud KMS"
- **Status:** `IMPLEMENTED WITH LOCAL DEV FALLBACK` | `UNVERIFIED-LIVE ON GCP`.
- **Reality:**
  - Envelope encryption logic using AES-256-GCM with 96-bit random IVs and 128-bit authentication tags is fully implemented in `backend/src/services/kms_envelope_encryption.ts`.
  - In local development and unit tests, it operates via `LocalDevKeyProvider` with an isolated master Key Encryption Key (KEK).
  - In `CloudKmsKeyProvider`, calling `wrapDek` or `unwrapDek` without active GCP credentials throws an explicit error (`KMS_UNAVAILABLE_ERROR`).
  - Claiming that templates are currently encrypted by Google Cloud KMS in production is **false until live GCP KMS credentials and IAM roles are configured in staging/production**.

### 2.4 Claim 4: "Immutable HMAC-SHA256 Audit Logs"
- **Status:** `TAMPER-EVIDENT` | `NOT IMMUTABLE`.
- **Reality:**
  - `AuditService` implements cryptographic hash chaining where each log node includes:
    $$H_n = \text{HMAC-SHA256}(K, H_{n-1} \parallel \text{seq} \parallel \text{timestamp} \parallel \text{eventData})$$
  - This provides **tamper-evidence**: if an attacker modifies an existing log entry, the chain links from that point forward fail cryptographic verification.
  - However, the logs are stored in a standard Firestore collection (`biometric_audit_logs`). A database administrator or compromised service account with Firestore delete permissions can delete the entire collection or truncate trailing documents.
  - True immutability requires **WORM (Write-Once-Read-Many) storage** (e.g. Google Cloud Storage Bucket Lock with retention policy).

---

## 3. AUDIT OF SECURE DATA FLOW & LEAKAGE RISKS

| Processing Boundary | Data Handled | Residual Leakage Risk | Mitigation Implemented |
|:---|:---|:---|:---|
| **Express Middleware** | Raw Base64 Request Body | Retained in V8 heap until GC | Memory limits enforced (`15mb`); no payload logging in production |
| **Audit Logger** | Audit Event Metadata | Accidental PII or raw image logging | `sanitizeAuditMetadata()` strips keys matching `/image\|base64\|buffer\|embedding\|vector\|probe\|raw/i` |
| **Firestore Repository**| User Profile & Biometric Vault | Unencrypted template exposure | Embedding stored as AES-256-GCM encrypted envelope; unit hypersphere vector never stored plaintext |
| **Duplicate Sheet UI** | Collision Interception Modal | Account enumeration / PII disclosure | Before ownership proof, raw UID is masked (`xK9***wXy`), phone is masked (`+91 ******2345`), name is masked (`Ana*** Kum**`) |
| **Crash Reporting** | Unhandled Error Payloads | Stack traces leaking image buffers | Global error handler returns generic typed responses (`ENROLLMENT_PROCESSING_ERROR`) without reflecting request bodies |

---

## 4. GOVERNANCE CONCLUSION

1. **Threshold Documentation Corrected:**
   - Operating thresholds must always be referred to as **Cosine Similarity** ($\cos \theta$), where higher values indicate closer match.
   - 1:1 Verification: $\text{Cosine Similarity} \ge 0.363$.
   - 1:N Duplicate Review: $\text{Cosine Similarity} \ge 0.740$.
   - 1:N Hard Block: $\text{Cosine Similarity} \ge 0.900$.
2. **Cryptographic Claims Refined:**
   - Audit logs are classified as **cryptographically tamper-evident**, not immutable.
   - In-memory image buffers are classified as **ephemeral RAM-only**, not immediately erased.
   - Template envelope encryption is classified as **implemented and verified with local provider**, awaiting live Cloud KMS staging validation.
