# KELASAGARA BIOMATCH V7: FAILURE MODES & EFFECTS ANALYSIS (FMEA)

**Document ID:** `FMEA-BIOMATCH-V7-001`  
**Phase:** Phase 2 (Requirements, Threat Model, SLOs, Tiers, Quota Math)  
**As-of Date:** 2026-10-10  
**Scope:** BioMatch End-to-End Pipeline (Capture $\rightarrow$ Quality $\rightarrow$ Liveness/PAD $\rightarrow$ Alignment $\rightarrow$ Neural Inference $\rightarrow$ 1:N Match $\rightarrow$ Persistence $\rightarrow$ Audit)  
**Methodology:** Standard FMEA scoring (IEC 60812 / AIAG-VDA):
- **Severity (S):** 1 (Negligible) to 10 (Hazardous / Catastrophic security breach without warning).
- **Occurrence (O):** 1 (Extremely unlikely) to 10 (Inevitably recurrent in daily operation).
- **Detection (D):** 1 (Automated immediate detection and containment) to 10 (Undetectable defect silently passing to client).
- **Risk Priority Number (RPN):** $\text{RPN} = S \times O \times D$ (Range: 1 to 1000). Priority threshold: $\text{RPN} \ge 100$ requires mandatory automated mitigation.

---

## 1. COMPREHENSIVE PIPELINE FMEA TABLE

| Stage # & Name | Failure Mode & Potential Root Cause | Effect on System / User | S (1-10) | O (1-10) | D (1-10) | RPN ($S \times O \times D$) | Architectural Mitigation & Fail-Closed Defense | Invariant ID | Owning Test ID & Status |
|---|---|---|---|---|---|---|---|---|---|
| **1. Capture & Framing** | **Extreme Head Pose Angle (Pitch > 25° or Yaw > 30°)**<br/>*Cause:* Subject holding phone at awkward angle or lying down. | Degraded embedding quality; false non-match or skewed feature extraction. | 5 | 8 | 2 | **80** | ML Kit real-time Euler angle filtering; client guides user with visual target overlay; frames rejected client-side before submission. | I-01 | `TEST-UI-001`<br/>*(Flutter Widget / ML Kit)* [IMPLEMENTED] |
| **1. Capture & Framing** | **Severe Lighting Imbalance / Underexposure**<br/>*Cause:* Backlight, direct sunlight glare, or dim room lighting. | Face detector fails or landmarks drift; high false rejection rate. | 6 | 7 | 3 | **126** | Laplacian variance blur detection + luminance histogram check; prompts user to move to a well-lit space. | I-01 | `TEST-IQA-001`<br/>*(Flutter IQA Test)* [IMPLEMENTED] |
| **2. Quality Assessment (IQA)** | **Low Inter-Pupillary Distance (IPD < 80 pixels)**<br/>*Cause:* User standing too far from selfie camera. | Insufficient pixel resolution for deep facial feature representation. | 6 | 6 | 2 | **72** | Minimum bounding box size enforced ($\ge 224 \times 224$ pixels); IPD threshold check $\ge 80\text{ px}$. | I-01 | `TEST-IQA-002`<br/>*(Flutter Unit Test)* [IMPLEMENTED] |
| **3. Liveness (PAD)** | **2D Static Print Attack (Printed Photo / Cutout)**<br/>*Cause:* Attacker presents printed A4 photo of victim's face. | Account takeover or identity spoofing if liveness fails. | 9 | 5 | 4 | **180** | Multi-frame Eye Aspect Ratio (EAR) blink tracking + texture frequency analysis + challenge response. | I-15, I-24 | `TEST-PAD-001`<br/>*(Flutter Biometric Unit)* [VERIFIED WORKING] |
| **4. Injection Defense (IAD)** | **Virtual Camera / Android Mock Video Injection**<br/>*Cause:* Rooted device or emulator routing pre-rendered video via v4l2loopback or OBS. | Complete bypass of physical camera capture; fake biometric enrollment. | 10 | 4 | 5 | **200** | Google Play Integrity (App Check) hardware attestation + camera metadata validation + server-issued nonce challenge. | I-04, I-05 | `TEST-IAD-001`<br/>*(Redteam Script)* [PLANNED] |
| **5. Preprocessing & Alignment** | **Landmark Coordinate Drift or Missing Landmark**<br/>*Cause:* Facial occlusion (mask, thick glasses, hand on face). | Affine transformation matrix singularity; distorted cropped face tensor. | 6 | 5 | 2 | **60** | Fail-closed validation of all 5 canonical landmark points; falls back to center-crop only if confidence > 0.95; otherwise returns `ALIGNMENT_FAILED`. | I-01 | `TEST-ALIGN-001`<br/>*(Backend Preprocessing Test)* [IMPLEMENTED] |
| **6. Neural Inference** | **ONNX Runtime Engine Crash or OOM**<br/>*Cause:* Memory spike, corrupted input buffer, or OS thread kill. | Enrollment process crashes; client receives unhandled 500 error. | 8 | 3 | 3 | **72** | Node.js process worker sandbox with supervisor auto-restart; try/catch block returns `TECHNICAL_FAILURE_RETRY`. | I-01 | `TEST-GOV-001`<br/>*(Backend Governance Test)* [VERIFIED WORKING] |
| **6. Neural Inference** | **Model Output Vector contains NaN / Infinite Values**<br/>*Cause:* Division by zero during L2 normalization or numerical instability. | Corrupts vector index; causes all subsequent cosine similarity comparisons to fail or produce garbage. | 9 | 2 | 2 | **36** | Assertive vector validation in `ModelRegistry`: checks `!isNaN(v) && isFinite(v)` for all 128 elements; verifies L2 norm $\approx 1.0 \pm 10^{-5}$. | I-01, I-18 | `TEST-GOV-001`<br/>*(Backend Governance Test)* [VERIFIED WORKING] |
| **6. Neural Inference** | **Uncalibrated Model Deployed in Production**<br/>*Cause:* Random-weight model or un-cleared checkpoint deployed. | System issues erroneous automated approvals or arbitrary denials. | 10 | 4 | 2 | **80** | Model Registry enforces `clearedForAutomatedApproval: false` on `RESEARCH_ONLY` models; hardcoded code assertion blocks automated status clearance. | I-01, I-07, I-18 | `TEST-GOV-001`<br/>*(Backend Governance Test)* [VERIFIED WORKING] |
| **7. 1:N Deduplication** | **Borderline Similarity Ambiguity (Score 0.65 to 0.74)**<br/>*Cause:* Close relatives, lookalikes, or identical twins. | Potential wrongful denial of legitimate worker or false duplicate pass. | 8 | 5 | 3 | **120** | Tri-state decision logic: Case routed to `PENDING_REVIEW` queue for dual human inspection; automated hard rejection avoided. | I-05, I-07 | `TEST-TRISTATE-001`<br/>*(Backend Unit Test)* [VERIFIED WORKING] |
| **7. 1:N Deduplication** | **Firestore Read Quota Exhaustion (Spark Limit 50k Reads)**<br/>*Cause:* Rapid 1:N enrollment scans on growing gallery without partition. | Entire application halted due to Firestore `RESOURCE_EXHAUSTED` (429). | 9 | 7 | 2 | **126** | Hard candidate scan ceiling ($K \le 500$); in-memory read counter circuit breaker degrades to asynchronous queue at 85% capacity. | I-19, I-27 | `TEST-QUOTA-001`<br/>*(Backend Circuit Breaker)* [IMPLEMENTED] |
| **8. Persistence & Rules** | **Direct Client Bypass of Verification Rules**<br/>*Cause:* Attacker writes `faceVerified=true` directly via REST API. | Complete biometric bypass; unverified worker marked as verified. | 10 | 6 | 1 | **60** | `firestore.rules` removes client write permission to all verification fields; only backend Admin SDK can write. Verified live on emulator. | I-02 | `TEST-RULES-001`<br/>*(Emulator Test)* [VERIFIED WORKING] |
| **8. Persistence & Rules** | **Network Dropout During Enrollment Commit**<br/>*Cause:* Flaky 3G/4G connectivity during Firestore document write. | Incomplete enrollment; template stored but user account not updated. | 7 | 6 | 2 | **84** | Idempotent transaction in `BiometricEnrollmentService`; client retries safely using identical session key; state reconciled automatically. | I-13, I-14 | `TEST-IDEMP-001`<br/>*(Backend Unit Test)* [IMPLEMENTED] |
| **8. Persistence & Rules** | **Audit Log Tampering / Deletion by Compromised Client**<br/>*Cause:* Client script attempts to delete duplicate match log entry. | Erased forensic trail; un-auditable fraudulent account creation. | 8 | 4 | 1 | **32** | `firestore.rules` enforces `allow read, write: if false` on `biometric_audit_logs`; client write rejected with HTTP 403. | I-17 | `TEST-AUDIT-001`<br/>*(Emulator Test)* [VERIFIED WORKING] |

---

## 2. HIGH-RPN PRIORITIZATION SUMMARY (RPN $\ge 100$)

The following 5 failure modes exceed the high-risk priority threshold ($\text{RPN} \ge 100$) and have mandatory architectural controls actively implemented or verified:

1. **Virtual Camera / Mock Video Injection (RPN = 200):** Mitigated by Firebase App Check (Play Integrity hardware verdict), client-server nonce freshness binding (I-04, I-05), and server-side neural inference (I-03).
2. **2D Static Print Spoof (RPN = 180):** Mitigated by multi-frame dynamic EAR blink sequence analysis and fail-closed quality thresholds (I-15, I-24).
3. **Lighting Imbalance & Contrast Glare (RPN = 126):** Mitigated by client-side real-time IQA frame rejection before submission.
4. **Spark Plan Read Quota Depletion (RPN = 126):** Mitigated by bounded candidate retrieval ($K \le 500$) and automated circuit breaker queueing (I-19, I-27).
5. **Borderline Duplicate Ambiguity (RPN = 120):** Mitigated by ADR-005 tri-state policy routing all matches between 0.65 and 0.74 to human review rather than automatic hard denial (I-07).
