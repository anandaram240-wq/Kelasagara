# GATE G7 REPORT: BIOMETRIC STORE SELECTION

**Subsystem:** Kelasagara BioMatch V7  
**Gate:** **Gate G7** (Phase 7: Biometric Store Selection)  
**Status:** **PASSED**  
**Release Readiness Level (RRL):** **RRL-0 (Research Prototype)**  
**Target Platform:** Firebase Spark Plan (Free Tier) | Sole Database: Cloud Firestore  
**Branch:** `biomatch/v7-hardening`  
**Date:** 2026-10-10  

---

### 1. SUMMARY SPECIFICATION

| Field | Detail |
|---|---|
| **Gate** | **Gate G7 (Phase 7)** |
| **Status** | **PASSED** |
| **Evidence IDs** | **EV-037** (`backend/src/tests/concurrency_vault_store.test.ts`), **EV-038** (`docs/biomatch/STORE_DECISION.md`) |
| **What Changed in Risk Register** | - **RISK-13 (Concurrent Race Double-Activation):** Mitigated and verified in test suite: Pending-inclusive search and monotonic lease locking prevent simultaneous same-face registrations from both becoming ACTIVE (Invariant I-12).<br/>- **RISK-14 (Database Platform Drift):** Disqualified external database candidates (pgvector, Qdrant, Milvus, Weaviate, OpenSearch). Formally established Cloud Firestore as the sole persistent database. |
| **Decisions Needed from Owner** | Owner confirmation of Candidate G selection: Cloud Firestore (`asia-south1` Mumbai) as the sole persistent vector store, with in-memory bounded candidate verification cache ($K \le 500$). Rejection of external databases confirmed. |
| **Next Step** | **Proceed autonomously to PHASE 8:** Data Architecture, Source of Truth, State Machine, Synchronization (`docs/biomatch/DATA_ARCHITECTURE.md`): formalize the enrollment state machine, atomic synchronization between `biometric_vault` and `users`, dual-write protections, and tamper-evident audit logging. |

---

### 2. GATE CRITERIA CHECKLIST

- [x] **Store Decision Matrix Authored:** 7 storage candidates evaluated in `docs/biomatch/STORE_DECISION.md`. External vector stores (PostgreSQL+pgvector, Qdrant, Milvus, Weaviate, OpenSearch) formally disqualified per non-negotiable Section 1.1 requirements and no-Blaze constraints.
- [x] **Candidate G Formally Selected:** Cloud Firestore Transactional Store with In-Process Bounded Verification Cache in `asia-south1` (Mumbai) selected as the sole persistent database.
- [x] **Exact Search Recall@k Guarantee:** Flat vector scan mathematically guarantees **$1.000$ recall@1** against ground truth (zero false uniques from approximate indexing). Verified in `concurrency_vault_store.test.ts`.
- [x] **Pending-Inclusive Concurrency Verified:** Test suite verified that concurrent same-face registration requests scan both committed vault and pending session vectors, intercepting racing duplicate enrollments.
- [x] **Monotonic Sequence Enforcement (Invariant I-12):** Proved in code that exactly one account achieves `ACTIVE` status under racing conditions; losing session is rejected.
- [x] **Crash Recovery Lease Operational:** Sessions utilize a 60-second lease timeout; abandoned crashed sessions automatically expire without deadlocking subsequent valid attempts.
- [x] **Template Envelope Protection (R-14):** Biometric templates stored in isolated collection `biometric_vault` inaccessible to client queries, with per-subject salt enabling crypto-shredding on DPDPA right-to-erasure requests.
