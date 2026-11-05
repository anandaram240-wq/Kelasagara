# KELASAGARA BIOMATCH — STAGE S9.5 FORMAL SECURITY CONTRACTS & TRUST-BOUNDARY SPECIFICATION
**Document ID:** `S9_SECURITY_CONTRACTS.md`  
**Classification:** Security Architecture & Invariant Catalog  
**Evaluation Date:** October 11, 2026 (UTC: 2026-10-11T05:07:30Z)  
**Git Commit:** `6a2a1482fe90d41050fc61ac83cc8777291a4a06` (tag: `s8-final`)  
**Evidence Artifact:** `evidence/s9/security_invariants.json`  

---

## 1. DATA-FLOW & TRUST-BOUNDARY ARCHITECTURE MAP

The Kelasagara BioMatch biometric pipeline operates across five distinct architectural security zones separated by rigorous trust boundaries:

```
[ ZONE 0: CLIENT PERIPHERAL & RUNTIME (Untrusted / Adversarial Environment) ]
   │
   ├── Flutter Camera Preview (Android CameraX / iOS AVFoundation)
   │     │ (Raw YUV/RGB frames captured at device lens)
   │     ▼
   ├── Android Platform APIs (Google Play Integrity Standard API)
   │     │ (Integrity token generated via Google Play Services daemon)
   │     ▼
   ├── Flutter BiometricService (`lib/services/biometric_service.dart`)
   │     │ (Computes captureDigest = SHA-256(burstBuffer))
   │     │ (Binds requestHash = SHA-256("${nonce}:${uid}:${action}:${captureDigest}"))
   │     │ (Packs FrameProvenancePayload)
   │     ▼
   ═══════ TRUST BOUNDARY 1: TLS 1.3 + Firebase Authentication Bearer Token ═══════
   │
[ ZONE 1: API GATEWAY & INGRESS CONTROL (Semi-Trusted Network Edge) ]
   │
   ├── Rate Limiter (Tier 0: 60 req/min IP sliding window)
   ├── Auth Middleware (`backend/src/routes/biometric_routes.ts`)
   │     │ (Validates Firebase ID token signature, tenant ID, and caller UID)
   │     ▼
   ├── Device Attestation Engine (`backend/src/services/device_attestation.ts`)
   │     │ (SEC-01: Verifies Play Integrity token authenticity)
   │     │ (SEC-02: Re-computes and verifies canonical requestHash <= 500 bytes)
   │     │ (SEC-03: Validates capture skew <= 60s, token age <= 180s)
   │     │ (Enforces MEETS_DEVICE_INTEGRITY / MEETS_STRONG_INTEGRITY)
   │     ▼
   ═══════ TRUST BOUNDARY 2: Process Boundary (Authorized Internal Services) ═══════
   │
[ ZONE 2: NEURAL INFERENCE & LIVENESS DEFENSE (Isolated Memory Space) ]
   │
   ├── Session Challenge Service (`session_challenge_service.ts`)
   │     │ (SEC-04: Consumes single-use challenge nonce atomically in Firestore)
   │     ▼
   ├── Server-Side Landmark & Liveness (`server_landmark_extractor.ts`)
   │     │ (Extracts 5 facial landmarks directly from pixel buffer; rejects client coords)
   │     │ (PAD Tier 1-3: motion entropy, micro-texture, gaze shift analysis)
   │     ▼
   ├── ONNX Runtime Inference (`face_inference.ts` / `face_preprocessing.ts`)
   │     │ (Preprocesses aligned 112x112 face crop)
   │     │ (Extracts 512-dimensional float32 vector via SFace FP32 primary model)
   │     │ (L2-normalizes embedding; asserts finite values and correct dimensions)
   │     ▼
   ═══════ TRUST BOUNDARY 3: Cryptographic Envelope Boundary ═══════
   │
[ ZONE 3: CRYPTOGRAPHIC VAULT & ENVELOPE ENCRYPTION (Zero Plaintext Persistence) ]
   │
   ├── Envelope Encryption Engine (`template_privacy.ts`)
   │     │ (Generates fresh 256-bit CSPRNG Data Encryption Key [DEK])
   │     │ (Generates fresh 96-bit CSPRNG IV)
   │     │ (Encodes canonical binary AAD: `BIOMATCH_AAD_V1` with TLV tags)
   │     │ (Binds Tenant ID, User UID, Algorithm ID, Key Version, Timestamp)
   │     │ (Encrypts 512-float vector using AES-256-GCM)
   │     ▼
   ├── Key Management Provider (`kms_key_provider.ts`)
   │     │ (SEC-07: Calls Google Cloud KMS or LocalDevKeyProvider to wrap DEK)
   │     │ (DEK wrapped with KEK and AAD context: returns 60-byte wrapped DEK buffer)
   │     │ (IMMEDIATELY ZEROIZES plaintext DEK in memory via `dek.fill(0)`)
   │     ▼
   ═══════ TRUST BOUNDARY 4: Persistent Storage & Audit Boundary ═══════
   │
[ ZONE 4: DATA PERSISTENCE & GOVERNANCE (Encrypted At Rest) ]
   │
   ├── Firestore Biometric Vault (`users/{uid}/biometricVault/default`)
   │     │ (Persists envelope: version "v3_kms_gcm", wrappedDek, ciphertext, iv, authTag)
   │     │ (Plaintext vectors and plaintext keys are NEVER written to disk)
   │     ▼
   ├── Tamper-Evident Audit Service (`tamper_evident_audit.ts`)
   │     │ (SEC-11: Logs audit records with correlation ID, masking sensitive vectors)
   │     ▼
   └── Administrative Review & Dispute Queue (`biometric_matching.ts`)
         │ (SEC-13: Ambiguous biometric duplicates routed to human KYC review)
         │ (Automated bans strictly forbidden per Invariant I-14)
```

---

## 2. FORMAL INVARIANT CATALOG (SEC-01 TO SEC-14)

### SEC-01: Request Authenticity
- **Purpose:** The backend must never accept client-decoded Play Integrity token claims or unverified client assertions as proof of hardware integrity.
- **Enforcing Component:** `backend/src/services/device_attestation.ts` (`DeviceAttestationService`, `PlayIntegrityVerifier`).
- **Positive Test:** `play_integrity_attestation.test.ts` ("should verify legitimate Play Integrity token with valid requestHash").
- **Negative Test:** `play_integrity_attestation.test.ts` ("should reject token when hooking or emulator signature detected").
- **Failure Consequence:** An attacker running on an emulator or rooted device using Frida/Xposed hooks can bypass attestation and inject synthetic video frames.
- **Release Gate:** `GATE-06` (Live Google Play Integrity).

### SEC-02: Request Binding
- **Purpose:** The verified `requestHash` inside the attestation verdict must strictly equal the server's independently calculated digest:
  $$\text{requestHash} = \text{SHA-256}(\text{nonce} \mathbin{\Vert} \text{uid} \mathbin{\Vert} \text{action} \mathbin{\Vert} \text{captureDigest})$$
  Google Play Integrity API limits `requestHash` to $\le 500$ bytes.
- **Enforcing Component:** `backend/src/services/device_attestation.ts` (`computeRequestHash`, `verifyRequestHash`).
- **Positive Test:** `play_integrity_attestation.test.ts` ("should verify canonical requestHash binding").
- **Negative Test:** `play_integrity_attestation.test.ts` ("should reject token when requestHash does not match expected value").
- **Failure Consequence:** Attackers can intercept authentic device tokens from legitimate sessions and replay them across different users, tenants, or operations.
- **Release Gate:** `GATE-06` (Live Google Play Integrity).

### SEC-03: Freshness
- **Purpose:** Stale or expired attestation tokens or capture payloads cannot authorize sensitive operations. Capture timestamps must be within 60s of submission; token timestamps must be within 180s.
- **Enforcing Component:** `backend/src/services/device_attestation.ts`.
- **Positive Test:** `play_integrity_attestation.test.ts` ("should accept token within 180s freshness window").
- **Negative Test:** `play_integrity_attestation.test.ts` ("should reject expired attestation token").
- **Failure Consequence:** Intercepted biometric submissions can be replayed long after the physical user has departed.
- **Release Gate:** `GATE-06` / `GATE-09`.

### SEC-04: Single-Use State
- **Purpose:** A single-use business challenge nonce cannot authorize multiple protected operations.
- **Enforcing Component:** `backend/src/services/session_challenge_service.ts` (`consumeChallenge`).
- **Positive Test:** `test_liveness_injection_bypass.test.ts` ("Test 1: Legitimate challenge-response passed successfully").
- **Negative Test:** `test_liveness_injection_bypass.test.ts` ("Test 2: Replay attack successfully intercepted and blocked [Invariant I-05]").
- **Failure Consequence:** Challenge replay vulnerability allowing duplicate unauthorized verification operations.
- **Release Gate:** `GATE-09` (Concurrency and Idempotency).

### SEC-05: Envelope Integrity
- **Purpose:** Any modification to ciphertext, nonce, authentication tag, or canonical AAD context must trigger instant cryptographic rejection.
- **Enforcing Component:** `backend/src/services/template_privacy.ts` (`decryptTemplateEnvelope`, `BIOMATCH_AAD_V1`).
- **Positive Test:** `aad_canonicalization.test.ts` ("should round-trip canonical AAD with exact binary equivalence").
- **Negative Test:** `aad_canonicalization.test.ts` ("should reject tampered binary AAD buffer").
- **Failure Consequence:** Ciphertext tampering or template substitution without detection.
- **Release Gate:** `GATE-02` (Cryptographic AAD) / `GATE-03` (Envelope Encryption).

### SEC-06: Tenant Isolation
- **Purpose:** Biometric templates belonging to Tenant A cannot be decrypted, queried, or matched by Tenant B. Tenant ID is bound as an immutable AAD tag in the cryptographic envelope.
- **Enforcing Component:** `backend/src/services/template_privacy.ts` (`TAG_TENANT_ID`), `cross_tenant_isolation.test.ts`.
- **Positive Test:** `cross_tenant_isolation.test.ts` ("Tenant A decrypts Tenant A template successfully").
- **Negative Test:** `cross_tenant_isolation.test.ts` ("Tenant B cannot decrypt Tenant A template with different tenant AAD context").
- **Failure Consequence:** Cross-tenant biometric data leakage and unlawful inter-organizational tracking.
- **Release Gate:** `GATE-07` (Cross-Tenant Authorization).

### SEC-07: Key Separation
- **Purpose:** Cloud KMS KEKs are never exported into application memory. Fresh 256-bit DEKs are used per template, wrapped via KMS, and immediately zeroized in memory (`dek.fill(0)`).
- **Enforcing Component:** `backend/src/services/kms_key_provider.ts`, `template_privacy.ts`.
- **Positive Test:** `template_migration.test.ts` ("MIG-02: Live migration commits valid v3_kms_gcm record and preserves vector fidelity").
- **Negative Test:** `template_migration.test.ts` (verifies persisted record contains `wrappedDek`, zero plaintext DEK fields).
- **Failure Consequence:** Full database dump exposes all historical facial embeddings to offline brute-force.
- **Release Gate:** `GATE-03` (Envelope Encryption) / `GATE-04` (Live Cloud KMS).

### SEC-08: Migration Atomicity
- **Purpose:** Migration from legacy formats (`v1_plain_gcm`, `v2_aad_gcm`) to `v3_kms_gcm` must be idempotent, atomic, and fail-safe without destroying source records.
- **Enforcing Component:** `backend/src/services/template_migration.ts` (`TemplateMigrationService`).
- **Positive Test:** `template_migration.test.ts` ("MIG-01: Dry-run migration previews v2 -> v3 conversion without altering original").
- **Negative Test:** `template_migration.test.ts` ("MIG-04: Migration fails safely when source ciphertext is corrupted without damaging state").
- **Failure Consequence:** Irreversible corruption of gig-worker biometric authentication records.
- **Release Gate:** `GATE-05` (Legacy Data Migration).

### SEC-09: Authorization
- **Purpose:** Knowing an account UID or document path confers zero authority; caller must present a valid Firebase Auth bearer token matching the targeted resource.
- **Enforcing Component:** `backend/src/routes/biometric_routes.ts` (`authMiddleware`), `firestore.rules`.
- **Positive Test:** `security_hardening.test.ts` ("Authenticated requests with valid tokens succeed").
- **Negative Test:** `security_hardening.test.ts` ("All 4 sensitive biometric endpoints fail-closed with 401 when Authorization header is omitted").
- **Failure Consequence:** Horizontal privilege escalation and unauthorized template deletion or matching.
- **Release Gate:** `GATE-07` / `GATE-08` (Firestore Security Rules).

### SEC-10: Version Integrity
- **Purpose:** Unsupported or unknown envelope schema versions are strictly rejected; no silent coercion or fallback to plaintext.
- **Enforcing Component:** `backend/src/services/template_privacy.ts` (`verifyEnvelopeVersion`).
- **Positive Test:** `template_migration.test.ts` ("MIG-05: Batch migration handles heterogeneous envelope batches").
- **Negative Test:** `template_privacy.ts` (throws error when envelope version is unknown or unsupported).
- **Failure Consequence:** Cryptographic downgrade attacks forcing vulnerable cipher modes.
- **Release Gate:** `GATE-03` (Envelope Encryption).

### SEC-11: Audit Privacy
- **Purpose:** Audit logs and system telemetry must never contain raw facial embeddings, base64 images, plaintext DEKs, or client authentication tokens.
- **Enforcing Component:** `backend/src/services/tamper_evident_audit.ts`, `audit_service.ts`.
- **Positive Test:** `test_manifest.json` (`tamper_evident_audit.test.ts`).
- **Negative Test:** `evidence/z06_secret_scan.json` (648 files scanned with 0 secrets or raw biometric payloads leaked).
- **Failure Consequence:** Biometric feature extraction leakage into SIEM, cloud storage, or log aggregators.
- **Release Gate:** `GATE-11` (Operational Recovery & Telemetry).

### SEC-12: Fail-Safe Behavior
- **Purpose:** If any security control fails (quality gate, attestation, AAD check, KMS unwrap), execution halts immediately in a fail-closed state.
- **Enforcing Component:** `backend/src/services/biometric_enrollment.ts`, `device_attestation.ts`.
- **Positive Test:** `pipeline_audit_ablations.test.ts` (pipeline aborts on any pre-check failure).
- **Negative Test:** `stage_s3_mutation_suite.test.ts` ("MUTANT-04 Quality gate bypass mutation is KILLED").
- **Failure Consequence:** Fail-open flaw permitting unverified or spoofed biometric samples into database.
- **Release Gate:** `GATE-11` (Operational Recovery).

### SEC-13: Human Review
- **Purpose:** High-similarity duplicate candidates never trigger automated account bans or fund forfeitures; all consequential actions step up to human KYC.
- **Enforcing Component:** `backend/src/services/biometric_matching.ts`, `lib/services/biometric_service.dart`.
- **Positive Test:** `biometric_matching.ts` (ambiguous match creates admin queue review ticket).
- **Negative Test:** Invariant I-14 audit (zero automated ban logic in biometric verification pathway).
- **Failure Consequence:** Severe algorithmic injustice and wrongful termination of vulnerable gig workers.
- **Release Gate:** `GATE-14` (Consequential Enforcement Authorization).

### SEC-14: Evidence Provenance
- **Purpose:** Every release decision claim must be grounded in an auditable command, SHA-256-verified evidence artifact, and verified environment.
- **Enforcing Component:** `evidence/s9/MANIFEST.json`, `S9_RELEASE_GATES.md`.
- **Positive Test:** `evidence/s9/baseline.json` (100% manifest match across all test artifacts).
- **Negative Test:** Missing staging credentials classified strictly as `EXTERNALLY_BLOCKED`.
- **Failure Consequence:** Fabricated security claims leading to unearned deployment confidence.
- **Release Gate:** `GATE-01` / `GATE-15` (Evidence-Based Release Decision).

---
*Report generated and validated under Stage S9.5 Operating Contract.*
