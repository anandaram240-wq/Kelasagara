# KELASAGARA V20.12: CASE MANAGEMENT LIFECYCLE & STATE MACHINE SPECIFICATION

**Project:** Kelasagara Biometric Security Architecture  
**Phase:** V20.12  
**Parent Phase:** V20.11 (`412def0`)  
**Working Branch:** `security/phase20.12-biometric-trust-provenance`  
**Classification:** Operational Security & Identity Lifecycle Specification  

---

## 1. FORMAL CASE LIFECYCLE STATE MACHINE

When an enrollment probe lands in the Ambiguous Review Zone ($0.363 \le \text{similarity} < 0.720$) or triggers a Duplicate Hard Block ($\text{similarity} \ge 0.720$), a support case document is created atomically in `biometric_duplicate_cases`.

The case progresses through a strictly validated transition graph:

```
                      +-------------------+
                      |      CREATED      |
                      +-------------------+
                                |
                   (Initiate OTP / Identity Check)
                                v
            +---------------------------------------+
            |    OWNERSHIP_VERIFICATION_PENDING     |
            +---------------------------------------+
                                |
                    (Verify SMS OTP / Aadhaar)
                                v
                      +-------------------+
                      |     VERIFIED      |
                      +-------------------+
                                |
                     (Assigned to Reviewer)
                                v
                      +-------------------+
                      |   UNDER_REVIEW    |
                      +-------------------+
                                |
         +----------------------+----------------------+
         |                                             |
 (Approve Distinct)                           (Confirm Duplicate)
         v                                             v
+-------------------+                         +-------------------+
|     RESOLVED      |                         |     REJECTED      |
+-------------------+                         +-------------------+
```

### Terminal Exit States
Any active state can transition to:
- `CANCELLED`: If applicant withdraws application.
- `EXPIRED`: If TTL expires ($t > \text{createdAtMs} + 30\text{ days}$).

---

## 2. STATE TRANSITION RULES & INVARIANTS

| State | Allowed Next States | Required Actor | Required Evidence / Guard |
| :--- | :--- | :--- | :--- |
| **`CREATED`** | `OWNERSHIP_VERIFICATION_PENDING`, `CANCELLED`, `EXPIRED` | System / Applicant | Case reference exists in `biometric_duplicate_cases`. |
| **`OWNERSHIP_VERIFICATION_PENDING`** | `VERIFIED`, `CANCELLED`, `EXPIRED` | System (Auth Service) | Valid verification details (`method: SMS_OTP` or `AADHAAR_OFFLINE_XML`). |
| **`VERIFIED`** | `UNDER_REVIEW`, `CANCELLED`, `EXPIRED` | Auditor / Dispatcher | `ownershipVerified === true` enforced. |
| **`UNDER_REVIEW`** | `RESOLVED`, `REJECTED`, `CANCELLED`, `EXPIRED` | `BIOMETRIC_AUDITOR`, `TRUST_AND_SAFETY_ADMIN` | Minimum 10-char justification; appends SHA-256 chained audit record. |
| **`RESOLVED`** | None (Terminal) | - | Immutable final state. |
| **`REJECTED`** | None (Terminal) | - | Immutable final state. |
| **`EXPIRED`** | None (Terminal) | - | Automatically fails closed when $t > \text{expiresAtMs}$. |
| **`CANCELLED`** | None (Terminal) | - | Immutable final state. |

---

## 3. IMMUTABLE SAFETY INVARIANTS

1. **Non-Locking Pre-Existing Account:**
   The existing matched account remains 100% active and unlocked throughout the entire review lifecycle (`existingAccountLocked: false`). An incoming stranger or malicious applicant cannot trigger account suspension or lockouts against legitimate workers.
2. **Zero Direct Jump to Resolution:**
   Attempting to transition directly from `CREATED` to `RESOLVED` throws `ERR_ILLEGAL_STATE_TRANSITION`. Ownership verification is mandatory.
3. **Cryptographic Audit Ledger:**
   Every review adjudication produces a cryptographically chained audit log entry:
   $$\text{entryHash} = \text{SHA-256}(\text{caseId} \parallel \text{applicantUid} \parallel \text{reviewerId} \parallel \text{decision} \parallel \text{justification} \parallel \text{prevHash} \parallel \text{timestamp})$$
   Integrity is verified via `verifyAuditChainIntegrity()`.
