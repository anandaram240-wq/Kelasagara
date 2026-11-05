# KELASAGARA BIOMATCH V7: DECISIONS & ARCHITECTURAL DECISION RECORDS (ADRs)

---

### ADR-001: Sole Persistent Database Platform is Cloud Firestore
- **Status:** Accepted (Non-negotiable).
- **Context:** Project owner specified strict Firebase-only persistence under no-Blaze constraints. External vector DBs (pgvector, Supabase, Milvus, Qdrant, MongoDB) are strictly prohibited.
- **Decision:** Cloud Firestore is the sole persistent store for all user profiles, biometric templates (`biometric_vault`), rate limits, and audit logs.
- **Consequences:** All vector storage and 1:N searches must conform to Firestore vector limits (max 2048-D, flat exact index) and adhere to the 50,000 reads/day Spark plan budget.

---

### ADR-002: Standalone Trusted Backend for Server-Authoritative Logic
- **Status:** Accepted.
- **Context:** Deploying Firebase Cloud Functions requires the Blaze plan (Google Cloud Artifact Registry & Cloud Build requirement, re-verified in EV-009). Upgrading to Blaze is blocked by the owner.
- **Decision:** The trusted server authority is implemented as a standalone Node.js/TypeScript service using `firebase-admin` and `onnxruntime-node`. It runs locally during development (and can deploy to free container compute if approved), communicating with Cloud Firestore via Firebase service account credentials.
- **Consequences:** Eliminates the Blaze plan dependency for compute while preserving Firebase Firestore as the database of record.

---

### ADR-003: Deprecation of Heuristic Fourier Landmark Encoder
- **Status:** Accepted.
- **Context:** Audit revealed that `BiometricService.generateEmbeddingFromLandmarks` uses a heuristic Fourier positional trigonometric formula on 7 facial ratios. It cannot achieve production-grade FMR/FNMR.
- **Decision:** Classify the Fourier landmark encoder as an interim operational placeholder for offline/UI testing only. Authoritative enrollment and duplicate screening must rely on neural feature extraction (MobileFaceNet ONNX).
- **Consequences:** Prevents false claims of production biometric accuracy.

---

### ADR-004: Elimination of Client-Writable `faceVerified` in Security Rules
- **Status:** Proposed / Pending Implementation.
- **Context:** Red-team test `security/redteam/test_i02_rules_vulnerability.ts` confirmed that `firestore.rules` (Branches 2C and 2D) currently permit client sessions to set `faceVerified=true` directly on their user document.
- **Decision:** Patch `firestore.rules` to remove `request.resource.data.faceVerified == true` from all client-accessible update rules. State advancement must be executed exclusively via backend Admin SDK.
- **Consequences:** Enforces Invariant I-02 (Server-authoritative approval) and prevents forged biometric approvals.

---

### ADR-005: Provisional Tri-State Thresholds (Review-First Policy)
- **Status:** Accepted.
- **Context:** The `0.74` duplicate threshold was proposed based on general research literature, but has not been empirically calibrated on consented Indian demographic datasets.
- **Decision:** The system must operate with a tri-state classification:
  - Similarity >= `0.74`: Duplicate detected (deny duplicate enrollment).
  - Similarity between `0.65` and `0.74`: Ambiguity / Manual Review required.
  - Similarity < `0.65`: Approved unique enrollment.
  Borderline cases must route to human review rather than automatic hard denial.
- **Consequences:** Mitigates the risk of false positives while dataset calibration is conducted.

---

### ADR-006: Standalone Backend Classified as Tier 0 (Dev/Shadow Prototype)
- **Status:** Accepted (Part 4.3).
- **Context:** The standalone Node.js backend runs locally or on unmanaged container compute. It lacks managed hardware security modules (HSMs), confidential compute, and enterprise high availability.
- **Decision:** The standalone backend is formally classified as **Tier 0 (Dev / Shadow / Non-authoritative prototype)**. It serves as an integration harness and shadow testing engine. It cannot make production-authoritative security claims until deployed on certified managed infrastructure (Tier 1/2).
- **Consequences:** Eliminates premature high-availability or production-readiness claims.

---

### ADR-007: Service Account Key Handling & Secret Zero Hygiene
- **Status:** Accepted.
- **Context:** The standalone backend requires Firebase Admin SDK credentials to interact with Cloud Firestore on Spark.
- **Decision:**
  - Service account JSON private keys must NEVER be placed in repository paths or committed to git.
  - `.gitignore` explicitly excludes `*serviceAccount*.json`, `*.pem`, `*.key`, and `.env.local`.
  - Local development connects to the Firebase Emulator Suite without real credentials (`FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`).
  - Automated security scans via `gitleaks` (`gitleaks git --verbose`) are run to verify that no secret keys enter git history.
- **Consequences:** Eliminates secret leakage risks during dev and shadow testing.

---

### ADR-008: Priority Invariant P0 Over P2 in Onboarding State Transitions
- **Status:** Accepted (V7 s0.1 Priority Order).
- **Context:** Legacy client methods (`setFaceVerified`, `setHirerFaceVerified`) relied on client writes to `faceVerified=true` in `firestore.rules`.
- **Decision:** Invariant I-02 (Server-authoritative approval; P0) strictly overrides legacy client convenience (P2). Client write rights to `faceVerified` are eliminated. Onboarding must proceed via `updateProfile` (`pending_profile` -> `pending_face`), then server-side enrollment via `BiometricService.instance.enrollBiometric()` (which invokes the backend Admin SDK to advance `accountStatus`), followed by client refresh.
- **Consequences:** Prevents client-forged approvals while maintaining seamless onboarding verified by live Firestore emulator tests.
