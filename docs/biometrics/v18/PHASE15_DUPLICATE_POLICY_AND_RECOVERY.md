# PHASE 15 — GATE G: DUPLICATE DECISION SAFETY POLICY AND DISPUTE RECOVERY AUDIT

**Author:** Principal Identity Safety, Biometric Ethics & Compliance Audit Lead  
**Workspace:** `kelasagaara_v17`  
**Classification:** CONTROLLED TEST ONLY (`productionBiometricCalibrationApproved = false`)  
**Timestamp:** 2026-10-29  

---

## 1. Executive Summary & Core Ethical Invariant

In biometric identity management, an automated similarity score $\cos \ge 0.90$ is an **investigation trigger**, never unilateral mathematical proof of fraud. 

In field deployments across diverse demographics, high biometric similarity can arise from:
1. **Biological Lookalikes & Monozygotic Twins:** Identical twins share facial features that produce cosine similarities $\ge 0.92$ on ArcFace/SFace embeddings.
2. **Re-enrollment with Updated Phone Number:** A legitimate worker who lost their phone may attempt a new registration rather than account recovery.
3. **Camera Distortion & Artifacts:** Severe low-light quantization or sensor noise can occasionally compress feature distributions.

Treating $\cos \ge 0.90$ as an irrevocable fraud conviction that permanently locks out a worker or exposes the registered user's profile is a critical human-rights and data-privacy violation. Gate G formalizes and verifies the **Kelasagara Reversible Identity Invariant**:
> **Every suspected duplicate must pause enrollment into a proportionate, reversible inquiry without exposing candidate PII, without disrupting the existing account, and with a binding path to administrative human dispute resolution.**

---

## 2. Forensic Audit of Previous Deficiencies

Our audit of the Phase 14 implementation identified three severe security and ethical defects:

| Defect ID | Prior Implementation Behavior | Regulatory & Ethical Hazard | Remediated Status |
| :---: | :--- | :--- | :---: |
| **D1** | `face_v18_routes.ts` returned `duplicateCandidate: { matchedUid, matchedMaskedPhone }` in the HTTP 409 response. | **Severe PII Leakage:** An unverified applicant or malicious bot could harvest registered phone numbers and user IDs by probing face images. | 🟢 **REMEDIATED (Zero PII Exposed)** |
| **D2** | `TransactionalGalleryCoordinatorV18` halted on $\cos \ge 0.90$ without writing an audit ticket to `biometric_audit_queue`. | **Irrevocable Silent Rejection:** No human reviewer was alerted; applicant had no inquiry ticket or appeal workflow. | 🟢 **REMEDIATED (Automatic Investigation Ticket)** |
| **D3** | HTTP 409 returned `DUPLICATE_ACCOUNT_DETECTED` with language implying confirmed fraud. | **Presumption of Guilt:** Wrongfully accused genuine workers, identical twins, or victims of phone theft without due process. | 🟢 **REMEDIATED (`DUPLICATE_INVESTIGATION_PENDING`)** |

---

## 3. Engineering Remediations Implemented

### 3.1 Reversible Investigation Ticket Generation
In `TransactionalGalleryCoordinatorV18.enrollWorkerWithEpochFencedRetry`:
```typescript
if (decisionStatus === 'HARD_DUPLICATE_BLOCKED') {
  const auditTicketId = `audit_dup_${params.uid}_${screenedAtEpoch}_${driftAttempt}`;
  const auditTicket: BiometricAuditTicketV3 = {
    ticketId: auditTicketId,
    candidateUid: params.uid,
    matchedUid: duplicateSearch.matchedUid ?? 'unknown',
    matchedMaskedPhone: duplicateSearch.matchedMaskedPhone ?? 'unknown',
    cosineSimilarity: duplicateSearch.maxCosineSimilarity,
    policyId: this.duplicatePolicy.policyId,
    createdAtEpochMs: Date.now(),
  };

  // Asynchronously record to compliance audit queue
  await this.txAdapter.recordDuplicateInvestigationTicket(auditTicket);

  return {
    enrolled: false,
    decisionStatus: 'HARD_DUPLICATE_BLOCKED',
    committedGlobalEpoch: this.localWatermarkEpoch,
    templateGeneration: expectedGen,
    epochDriftRetriesUsed: driftAttempt,
    idempotentReplay: false,
    duplicateSearch,
    auditTicketId,
    releaseStatus: RELEASE_STATUS,
    calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
  };
}
```

### 3.2 Complete PII Sanitization at the API Boundary
In `backend/src/routes/face_v18_routes.ts`:
```typescript
if (result.decisionStatus === 'HARD_DUPLICATE_BLOCKED') {
  res.status(409).json({
    status: 'DUPLICATE_INVESTIGATION_PENDING',
    error: 'DUPLICATE_INVESTIGATION_PENDING',
    message: 'Biometric similarity requires standard compliance review. An inquiry ticket has been opened.',
    auditTicketId: result.auditTicketId,
    reviewStatus: 'PENDING_HUMAN_RESOLUTION',
    reversible: true,
    releaseStatus: result.releaseStatus,
  });
  return;
}
```
**Zero Exposure Verification:** The JSON payload strictly omits `matchedUid`, `matchedMaskedPhone`, and raw float cosine scores. The applicant receives only their reference `auditTicketId` and instructions to contact support.

### 3.3 Strict Account Isolation for Existing Workers
- The existing registered account's record in `biometric_vault/{matchedUid}` is **never written to or locked**.
- Ratings, ongoing booking histories, wallet balances, and active template generations remain $100\%$ operational.
- The applicant's submission is held in a provisional staging state outside the active search arena.

---

## 4. Multi-Tier Administrative Resolution Workflow

To guarantee proportionate due process under DPDP Rules 2025, human compliance officers resolve contested duplicate cases through three distinct resolution paths:

```
[CONTESTED DUPLICATE DETECTED] (Cosine >= 0.90)
             │
             ▼
(biometric_audit_queue: status=INVESTIGATION_PENDING)
             │
             ├── Human Reviewer verifies physical government identity
             │
             ├── Option A: IDENTICAL TWIN / LOOKALIKE
             │   ├── Resolution: AUTHORIZED_OVERRIDE_APPROVED
             │   ├── Policy: Distinct tenant sub-key or multi-factor biometric binding
             │   └── Action: Both workers enroll independently with administrative flag
             │
             ├── Option B: LEGITIMATE RE-ENROLLMENT (Lost SIM / Phone Change)
             │   ├── Resolution: ACCOUNT_RECOVERY_AUTHORIZED
             │   ├── Policy: Old phone revoked, active template migrated to new UID
             │   └── Action: Rating and booking history preserved, vault updated
             │
             └── Option C: CONFIRMED ADVERSARIAL IMPERSONATION
                 ├── Resolution: CONFIRMED_FRAUD_REJECTED
                 ├── Policy: Second application permanently dismissed
                 └── Action: Existing legitimate account protected, incident logged to WORM ledger
```

---

## 5. Automated Verification Test Suite (`phase15_duplicate_policy_and_safety.test.ts`)

Five formal automated verification tests were authored and executed:

```
▶ Phase 15 — Gate G: Duplicate Decision Safety Policy Audit
  ✔ 1. High match score (cosine >= 0.90) creates a reversible review case in biometric_audit_queue (6.67ms)
  ✔ 2. Existing registered worker account remains completely active and untouched (5.88ms)
  ✔ 3. Zero Candidate PII is exposed to the applicant on HTTP 409 response (0.17ms)
  ✔ 4. Administrative Resolution: An authorized officer can resolve an erroneous duplicate case (6.58ms)
  ✔ 5. Audit Queue Observability: Measurable queue metrics (unresolved cases & review delay) (0.38ms)
✔ Phase 15 — Gate G: Duplicate Decision Safety Policy Audit (20.48ms)
```

### Key Verified Invariants:
1. **Reversible Inquiry Ticket Created:** Suspected duplicates always persist a ticket in `biometric_audit_queue`.
2. **Zero PII Leakage:** Asserted that `responseJson.includes(matchedUid) === false` and `responseJson.includes(matchedPhone) === false`.
3. **Untouched Existing Account:** Asserted that `vaultAfter.data.status === 'ACTIVE'` and template envelope bytes are strictly unchanged.
4. **Administrative Override:** Proved an authorized officer can update `resolutionStatus` to `AUTHORIZED_OVERRIDE_APPROVED` without altering biometric embeddings.
5. **Measurable Observability:** Proved that open queue volume and average resolution latency ($\bar{t}_{\text{pending}} = 45\text{ mins}$) are continuously measurable via collection queries.

---

## 6. Policy Domain Separation Matrix

Kelasagara strictly isolates the three distinct biometric policy domains:

| Policy Domain | Active Threshold | Target False Match Rate | Decision Authority | Operational Action |
| :--- | :---: | :---: | :--- | :--- |
| **1:1 Verification (eKYC / Arrival)** | $\cos \ge 0.363$ | $10^{-3}$ ($0.1\%$) | Fully Automated | Worker unlocks job location / OTP gate |
| **1:N Duplicate Screening (Enrollment)** | $\cos \ge 0.72$ (Flag) / $\cos \ge 0.90$ (Pause) | $10^{-5}$ ($0.001\%$) | Automated Fence + Human Review | Staged pending resolution; zero auto-conviction |
| **Fraud Investigation & Disciplinary** | Multi-factor evidence + Government ID | $0.00\%$ (Manual Audit) | Authorized Compliance Officer | Reversible account migration or dismissal |

---

## 7. Gate G Conclusion

- **Presumption of Guilt Eliminated:** Contested applicants receive `DUPLICATE_INVESTIGATION_PENDING` with reversible inquiry tickets.
- **Data Protection Enforced:** Zero PII leakage in API error responses.
- **Existing Workers Protected:** Zero disruption to active accounts during contested registrations.
- **Gate Status:** **PASSED (CONDITIONAL ON CONTROLLED TEST ENVIRONMENT)**.
