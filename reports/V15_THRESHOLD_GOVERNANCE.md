# KELASAGARA V15.0 BIOMETRIC ENGINE AUDIT
# REPORT 02: THRESHOLD GOVERNANCE & CONFIGURATION AUDIT

**Document ID:** KLS-V15-THRESH-001  
**Classification:** ARCHITECTURAL SPECIFICATION & AUDIT  
**Target Subsystems:** `backend/src/config.ts`, `backend/src/services/account_lifecycle.ts`, `backend/src/services/biometric_matching.ts`, `backend/src/routes/face_routes.ts`  
**Base Commit Verified:** `e59cda4`  
**Audit Date:** 2026-10-23  

---

## 1. THE BIOMETRIC THRESHOLD TRIPTYCH

Biometric recognition systems must rigorously distinguish between **one-to-one (1:1) verification** (verifying that a claimant is the specific person they claim to be) and **one-to-many (1:N) duplicate detection** (searching an entire gallery to detect whether a person has enrolled under another identity).

In the OpenCV SFace architecture, embeddings lie on a 128-dimensional unit hypersphere ($\mathbb{S}^{127}$). The similarity metric is the inner product (dot product), which is identical to the cosine similarity:

$$\text{Sim}(\vec{u}, \vec{v}) = \frac{\vec{u} \cdot \vec{v}}{\|\vec{u}\|_2 \|\vec{v}\|_2} = \sum_{i=1}^{128} u_i v_i \in [-1.0, 1.0]$$

Kelasagara establishes three distinct, governed decision boundaries:

```
Cosine Similarity Range: [-1.0 .............................................................. +1.0]
-----------------------------------------------------------------------------------------------
[-1.0 ............. 0.363) : NON-MATCH (1:1 Verification Rejected)
[0.363 ............ 0.740) : VERIFIED MATCH (Legitimate Worker Verification Pass; Safe from Duplicate)
[0.740 ............ 0.900) : DUPLICATE SUSPECT / SOFT FLAG (Manual KYC Review Queued; Worker Not Hard Blocked)
[0.900 ............ 1.000] : HARD DUPLICATE FRAUD BLOCK (Unambiguous Identity Collision; Automatic Block)
-----------------------------------------------------------------------------------------------
```

### Mathematical Definitions:
1. **$\tau_{\text{verify}} = 0.363$ (Verification Threshold):**  
   The reference cosine threshold defined by the OpenCV SFace model specification. If $\text{Sim}(\vec{u}_{\text{probe}}, \vec{u}_{\text{enrolled}}) \ge 0.363$, the 1:1 claimant is authenticated as the account owner.
2. **$\tau_{\text{dup}} = 0.740$ (Duplicate Screening Threshold):**  
   The threshold for flagging cross-account duplicate claimants during enrollment or background audits. A score between $0.74$ and $0.90$ prompts human operator review without immediate lockout.
3. **$\tau_{\text{hard}} = 0.900$ (Hard Fraud Block Threshold):**  
   The threshold representing near-identical facial geometry, indicating intentional Sybil enrollment or extreme twin similarity. Triggers immediate registration termination and fraud incident logging.

---

## 2. SECONDARY CONFLATION DEFECT IN `account_lifecycle.ts`

### 2.1 The Discovery
During the V14 audit, the endpoint `/api/biometrics/verify-1to1` in `backend/src/routes/face_routes.ts` was corrected from using `duplicateThreshold` (`0.74`) to `verificationThreshold` (`0.363`). However, an audit of the entire backend codebase uncovered a lingering secondary defect in `backend/src/services/account_lifecycle.ts`.

In `AccountLifecycleService.reVerifyWorker`:
```typescript
// DEFECTIVE IMPLEMENTATION (Pre-V15):
export async function reVerifyWorker(uid: string, probeEmbedding: number[]): Promise<ReVerificationResult> {
  const enrolledTemplate = await FirestoreBiometricRepository.getTemplate(uid);
  if (!enrolledTemplate) throw new Error('NOT_ENROLLED');
  
  const similarity = cosineSimilarity(probeEmbedding, enrolledTemplate.vector);
  // BUG: Using duplicateThreshold (0.74) instead of verificationThreshold (0.363)!
  const passed = similarity >= config.duplicateThreshold; 
  
  return { passed, similarity, threshold: config.duplicateThreshold };
}
```

### 2.2 Forensic Impact Analysis
- **Worker Lockout:** A genuine worker returning for an on-shift identity re-verification presenting an authentic face with a legitimate cosine similarity of $0.52$ (well above the required $0.363$) would be falsely rejected (`passed = false`) because $0.52 < 0.74$.
- **False Rejection Rate (FRR) Catastrophe:** On-shift re-verification would experience an estimated FRR of 40–60%, locking out honest workers in varying lighting conditions.

### 2.3 The V15 Remediation
`backend/src/services/account_lifecycle.ts` was updated to consume `config.verificationThreshold`:
```typescript
// REMEDIATED IMPLEMENTATION (V15.0):
export async function reVerifyWorker(uid: string, probeEmbedding: number[]): Promise<ReVerificationResult> {
  const enrolledTemplate = await FirestoreBiometricRepository.getTemplate(uid);
  if (!enrolledTemplate) throw new Error('NOT_ENROLLED');
  
  const similarity = cosineSimilarity(probeEmbedding, enrolledTemplate.vector);
  // CORRECTED: Evaluates against verificationThreshold (0.363)
  const passed = similarity >= config.verificationThreshold; 
  
  return { 
    passed, 
    similarity, 
    threshold: config.verificationThreshold,
    governance: 'V15_VERIFICATION_GOVERNED'
  };
}
```
This fix was verified with a targeted regression test (`threshold_governance.test.ts`) that asserts an authentic similarity of $0.50$ passes on-shift verification.

---

## 3. STRICT CONFIGURATION VALIDATION IN `config.ts`

To prevent misconfigurations, environment corruption, and deployment errors, `backend/src/config.ts` was hardened with strict threshold parsing and mathematical invariance checks.

### 3.1 Strict Value Parsing (`parseThreshold`)
```typescript
function parseThreshold(
  raw: string | undefined, 
  defaultValue: number, 
  fieldName: string
): number {
  if (raw === undefined || raw === null || raw.trim() === '') {
    return defaultValue;
  }
  const parsed = Number(raw.trim());
  if (isNaN(parsed) || !isFinite(parsed)) {
    throw new Error(
      `[ThresholdGovernance] Invalid numeric value for ${fieldName}: "${raw}". Value must be a valid float.`
    );
  }
  if (parsed < -1.0 || parsed > 1.0) {
    throw new Error(
      `[ThresholdGovernance] Out-of-bounds value for ${fieldName}: ${parsed}. Cosine similarity must be in range [-1.0, 1.0].`
    );
  }
  return parsed;
}
```

### 3.2 Monotonic Invariance Enforcement (`validateThresholdGovernance`)
The system mandates that the three thresholds maintain a strictly increasing monotonic order:

$$\tau_{\text{verify}} < \tau_{\text{dup}} < \tau_{\text{hard}}$$

```typescript
export function validateThresholdGovernance(cfg: AppConfig): void {
  const { verificationThreshold, duplicateThreshold, hardBlockThreshold } = cfg;

  if (verificationThreshold >= duplicateThreshold) {
    throw new Error(
      `[ThresholdGovernance] Invariance Violation: verificationThreshold (${verificationThreshold}) must be strictly less than duplicateThreshold (${duplicateThreshold}).`
    );
  }

  if (duplicateThreshold >= hardBlockThreshold) {
    throw new Error(
      `[ThresholdGovernance] Invariance Violation: duplicateThreshold (${duplicateThreshold}) must be strictly less than hardBlockThreshold (${hardBlockThreshold}).`
    );
  }

  // Production Gating Fail-Safe
  if (cfg.nodeEnv === 'production' && !cfg.productionBiometricCalibrationApproved) {
    throw new Error(
      `[ThresholdGovernance] RELEASE BLOCKER: System is running in NODE_ENV=production, but PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED is false. Live identity gating is prohibited until empirical field calibration is complete.`
    );
  }
}
```

---

## 4. AUDIT OF DECISION DISPATCHING IN `biometric_matching.ts`

`backend/src/services/biometric_matching.ts` was reviewed to confirm complete decoupling between 1:1 verification and 1:N duplicate detection.

- **`evaluateVerification(similarity: number): VerificationResult`**
  - Evaluates `similarity >= config.verificationThreshold` (`0.363`).
  - Returns `{ isMatch: boolean, score: number, threshold: number }`.
  - Used exclusively by 1:1 authentication paths (`/verify-1to1`, `/reverify-shift`).

- **`evaluateDuplicateCandidate(similarity: number): DuplicateEvaluation`**
  - Evaluates `similarity >= config.hardBlockThreshold` (`0.90`) $\to$ Hard Fraud Block.
  - Evaluates `similarity >= config.duplicateThreshold` (`0.74`) $\to$ Soft Review Flag.
  - Used exclusively by 1:N deduplication paths (`/enroll-biometric`, `/cross-account-check`).

---

## 5. SUMMARY OF GOVERNANCE GUARANTEES

1. **No Silent Fallbacks:** Invalid environment variables (`NaN`, `Infinity`, text strings, numbers outside `[-1.0, 1.0]`) throw fatal startup exceptions rather than defaulting silently.
2. **Monotonicity Enforced:** Inverting thresholds or setting duplicate screening lower than verification fails fast at process initialization.
3. **Fail-Safe Production Lock:** A production container running with `NODE_ENV=production` will terminate on boot unless `PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED=true` is explicitly provided, ensuring no accidental live rollout.
