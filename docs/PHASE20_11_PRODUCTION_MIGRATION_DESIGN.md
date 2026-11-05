# PHASE 20.11: PRODUCTION DATA SAFETY & MIGRATION DESIGN
**Role:** Principal Data Architect & Backend Security Engineer  
**System:** Kelasagara Multi-Factor Biometric Identity Platform  
**Branch:** `security/phase20.11-legacy-template-isolation`  
**Date:** November 1, 2026  

---

## 1. NON-NEGOTIABLE SAFETY CONSTRAINTS

1. **Zero Production Writes:** This design is purely architectural. No live production databases or Firebase configurations were touched during Phase 20.11.
2. **Fail-Closed Migration Boundary:** No existing biometric record shall be deleted, modified, or migrated in place without explicit cryptographic validation and human review.
3. **Zero Production Downtime:** The transition must occur transparently via read-side gallery isolation and lazy on-demand re-enrollment.

---

## 2. PRODUCTION MIGRATION ARCHITECTURE

Instead of an aggressive, destructive one-time batch write to production Firestore records, the recommended migration follows a three-stage zero-risk strategy:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STAGE 1: READ-SIDE GALLERY ISOLATION (ZERO PRODUCTION WRITES)               │
│ - Deploy updated code with INCOMPATIBLE_EMBEDDING_SPACE = NEVER_COMPARE.    │
│ - Unmarked / legacy templates are automatically skipped in 1:N queries.     │
│ - False duplicates are eliminated immediately upon service boot.            │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ STAGE 2: PASSIVE INVENTORY & CLASSIFICATION AUDIT SCRIPT                   │
│ - Read-only script scans collection 'biometric_vault'.                      │
│ - Generates forensic manifest of templates:                                 │
│     * Total Active Templates                                                │
│     * Count of Canonical V2 Templates                                       │
│     * Count of Defective Pre-Hotfix Full-Photo Resize Templates             │
│     * Count of Legacy Landmark Space Templates                              │
│     * Count of Unverified / Ambiguous Templates                             │
│ - Produces audit ledger in Cloud Storage without writing to documents.      │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ STAGE 3: LAZY RE-ENROLLMENT & ATOMIC UPGRADE ON USER LOGIN                  │
│ - When existing user logs in via OTP/password:                             │
│     * System detects legacy/unmarked template.                              │
│     * Displays non-blocking notification: "Upgrade your face profile".       │
│     * User captures face with new YuNet+Umeyama camera pipeline.            │
│     * Authorized replacement atomically supersedes legacy record.           │
│     * Zero disruption to active marketplace shifts or bookings.             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. ROLLOUT PHASES & MONITORING GATES

| Phase | Action | Rollback Trigger | Safety Mitigation |
| :--- | :--- | :--- | :--- |
| **Phase 1: Read Isolation** | Deploy code with space classification | Any increase in false rejection rate | Revert to previous branch |
| **Phase 2: Inventory Audit** | Execute read-only batch scanner | Database read throttling | Limit query pages to 100 docs / second |
| **Phase 3: Worker Upgrade** | Enable in-app face re-enrollment prompt | Duplicate block spike | Re-enrollment uses isolated atomic replacement |
