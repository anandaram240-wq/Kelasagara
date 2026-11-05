# PHASE 20.19: DUAL-CUSTODY IDENTITY ASSURANCE & FIVE-TIER EVIDENCE RECONCILIATION

## 1. Threat Model & Recovery Authorization Risks

In biometric identity recovery, duplicate account resolution, and privileged account reactivation, two-person authorization (2PA) prevents unilateral insider takeovers. However, software verification often conflates algorithmic checks with real-world organizational security.

To ensure rigorous defense-in-depth, Phase 20.19 formally distinguishes **five distinct tiers of dual-custody assurance**:

```
+--------------------------------------------------------------------------------------------------+
| FIVE TIERS OF DUAL-CUSTODY ASSURANCE                                                             |
+--------+------------------------------------+--------------------------+-------------------------+
| Tier   | Assurance Scope                    | Verification Method      | Current Status          |
+--------+------------------------------------+--------------------------+-------------------------+
| Tier 1 | Mock Officer Registry Verification | Unit & Integration Tests | VERIFIED (Gate A)       |
| Tier 2 | Software-Level Identity Separation | Algorithmic Rules Engine | VERIFIED (Gate A)       |
| Tier 3 | Actual Organizational Identity Reg | Enterprise IdP (Okta/WS) | UNVERIFIED (Under Gate D)|
| Tier 4 | Real Hardware MFA Enrollment       | Physical FIDO2 Tokens    | UNVERIFIED (Under Gate D)|
| Tier 5 | Independent Human Authorization    | Procedural Out-of-Band   | UNVERIFIED (Under Gate D)|
+--------+------------------------------------+--------------------------+-------------------------+
```

---

## 2. Exhaustive Tier Definitions

### Tier 1: Mock Officer Registry Verification (Software Test Level)
- **Scope:** Validates the registry interface contract (`IOfficerAuthorizationRegistry`) using in-memory mock datasets (`InMemoryOfficerRegistry`).
- **Evidence:** Verified in Track B of `phase20_19_pilot_gate_a_closure.test.ts`. Proves that when the registry is unavailable, returns a suspended officer, or returns a revoked officer, authorization fails closed immediately.

### Tier 2: Software-Level Identity Separation (Algorithmic Policy Level)
- **Scope:** Enforced by `RecoveryDualCustodyEngineV19` (`backend/src/services/recovery_dual_custody_v19.ts`).
- **Policy Rules:**
  1. *Requester Self-Approval Prohibition:* An officer who initiates a recovery request (`requesterOfficerId`) cannot sign as an approver (`ERR_REQUESTER_SELF_APPROVAL`).
  2. *Distinct Officer IDs:* The two approving officers must possess different `officerId` strings (`ERR_IDENTICAL_APPROVER_IDENTITIES`).
  3. *Distinct IdP Subjects:* The two approving officers cannot share the same enterprise IdP subject (`ERR_COLLUSION_SAME_IDP_SUBJECT`).
  4. *Distinct MFA Credentials:* The two approving officers cannot share the same hardware MFA token (`ERR_COLLUSION_SHARED_MFA_CREDENTIAL`).
  5. *Canonical Context Binding:* Cryptographic RSA-PSS signatures bind target UID, case reference, recovery operation, requested phone number, request digest, and operation ID.
  6. *Single-Use Anti-Replay:* Consumed tokens and operation IDs are marked used; replayed tokens fail closed (`ERR_REPLAYED_RECOVERY_TOKEN`).

### Tier 3: Actual Organizational Identity Registration (Directory Level)
- **Scope:** Integration with the organization's live Identity Provider (e.g. Google Workspace, Okta, Azure AD). Requires provisioning named accounts, enforcing enterprise lifecycle status, and binding immutable employee IDs.
- **Gate Placement:** Strictly governed under **Gate D (Institutional, Legal and Human Pilot Authorization)**. Remains **UNVERIFIED** until live IdP integration is provisioned.

### Tier 4: Real Hardware MFA Enrollment (Physical Hardware Level)
- **Scope:** Provisioning and physical binding of dedicated FIDO2 / WebAuthn hardware authenticators (e.g. YubiKey 5 Series) to the two designated security officers (Biometric Compliance Officer and Independent Security Auditor).
- **Gate Placement:** Strictly governed under **Gate D**. Software mock IDs in unit tests do NOT satisfy physical token qualification.

### Tier 5: Independent Human Authorization (Human Governance Level)
- **Scope:** Two independent human beings with independent reporting lines exercising individual judgment, verifying case documentation, and performing out-of-band verification (e.g. telephonic confirmation) before signing.
- **Gate Placement:** Strictly governed under **Gate D**.

---

## 3. Honest Anti-Collusion Disclosure (Technical Controls Do Not Eliminate Collusion)

> [!CRITICAL]
> **Technical controls CANNOT eliminate human collusion.**
> Software-level separation cryptographically proves that two distinct cryptographic keys associated with distinct IdP subjects and distinct MFA identifiers signed the authorization payload.
> However, if two authorized individuals deliberately conspire to approve an illicit recovery, no mathematical algorithm or software check can prevent that collusion.
> Collusion mitigation fundamentally requires organizational governance: independent reporting structures, separate departmental oversight, out-of-band confirmation procedures, strict legal accountability, and tamper-evident audit logging.

---

## 4. Test Evidence

Track B of `phase20_19_pilot_gate_a_closure.test.ts` validates the Tier 1 and Tier 2 contracts across 10 tests:
- **Test 9:** Unavailable registry fails closed immediately (PASS).
- **Test 10:** Requester self-approval is rejected (PASS).
- **Test 11:** Suspended officer in registry is rejected (PASS).
- **Test 12:** Revoked officer in registry is rejected (PASS).
- **Test 13:** Approvers sharing same IdP subject are rejected (PASS).
- **Test 14:** Approvers sharing same MFA credential are rejected (PASS).
- **Test 15:** Altered request digest fails cryptographic signature verification (PASS).
- **Test 16:** Altered replacement phone number fails verification (PASS).
- **Test 17:** Two distinct, active, registered officers with valid signatures are approved (PASS).
- **Test 18:** Replayed recovery token is rejected via single-use fence (PASS).
