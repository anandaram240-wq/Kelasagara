# KELASAGARA BIOMETRIC ENGINE V10.0
# Complete Biometric System Architecture Specification
## Aadhaar-Inspired Multi-Tier Separation of Capture, Verification, Duplicate Screening, and Vault Protection

**Document ID:** `REP-ARCH-V10-01`  
**System:** Kelasagara Biometric Platform  
**Architecture Paradigm:** UIDAI Aadhaar Face RD Inspired 4-Tier Separation  
**Standard Framework:** ISO/IEC 19795-1, ISO/IEC 30107-3, ISO/IEC 24745, DPDPA 2023  
**Status:** Approved System Architecture  
**Version:** 10.0.0-PROD  
**Date:** 2026-10-22  

---

## 1. Architectural Overview & UIDAI Face RD Inspiration

The architecture of the Kelasagara Biometric Engine V10.0 is directly inspired by the publicly documented architecture of **UIDAI Aadhaar Face Authentication**. 

UIDAI's core insight is that **the mobile face capture component is NOT itself the recognition model**. UIDAI enforces a rigorous architectural separation between:
1. **The Registered Device (Face RD) Capture Component:** Guides user capture, validates lighting/pose quality, executes challenge-response liveness (blinking), binds telemetry into an encrypted PID block with single-use transaction hashes (WADH), and returns it to the application.
2. **The Requesting Application (AUA / KUA):** The business application handling user workflows and profile state.
3. **The Requesting Agency Backend (ASA / AUA Server):** Secure gateway routing requests without exposing biometric data.
4. **The Central Identity Data Repository (CIDR Matcher):** Secure, server-side biometric matching against enrolled master records.

Kelasagara realizes this identical architectural separation as a standalone enterprise platform with its own models, identities, and security boundaries.

```
+----------------------------------------------------------------------------------------------------+
|                                  KELASAGARA 4-TIER BIOMETRIC ARCHITECTURE                          |
+----------------------------------------------------------------------------------------------------+
                                                                                                      
  [TIER 1: TRUSTED CAPTURE COMPONENT (RD EQUIVALENT)]                                                 
  ┌─────────────────────────────────────────────────────────────────────────────────┐                 
  │  face_enrollment_screen.dart & advanced_landmark_analyzer.dart                  │                 
  │  - Hardware Camera Stream (YUV_420_888)                                         │                 
  │  - ISO/IEC 29794-5 OFIQ Quality Gate (IPD ≥ 90px, |yaw| ≤ 5°, |pitch| ≤ 5°)     │                 
  │  - ISO/IEC 30107-3 Active Kinematic Blink PAD (EAR: open ≥ 0.58, close ≤ 0.28)  │                 
  │  - Passive Laplacian Texture Variance (σ²L ∈ [110, 1200])                       │                 
  │  - Umeyama Procrustes Canonical 2D Alignment                                    │                 
  │  - Whitened Procrustes Gaussian Orthogonal Linear Projection onto S^127         │                 
  │  - WADH RequestHash Binding: SHA256(uid + nonce + digest + σ²L + IPD)           │                 
  └──────────────────────────────────────┬──────────────────────────────────────────┘                 
                                         │ Secure In-Memory Transfer                                  
                                         ▼                                                            
  [TIER 2: REQUESTING APPLICATION (AUA EQUIVALENT)]                                                   
  ┌─────────────────────────────────────────────────────────────────────────────────┐                 
  │  Kelasagara Mobile Client (Flutter)                                             │                 
  │  - AuthProvider & BiometricService                                              │                 
  │  - DPDPA 2023 Explicit Verifiable Consent Modal                                 │                 
  │  - Zero raw image disk persistence (pixels zeroed post-inference)               │                 
  │  - DuplicateDetectedSheet (Masked Display ID: KLS-xK9***wXy-7890)               │                 
  └──────────────────────────────────────┬──────────────────────────────────────────┘                 
                                         │ HTTPS / TLS 1.3 + Firebase Bearer Token                    
                                         ▼                                                            
  [TIER 3: BACKEND RECOGNITION & SCREENING (CIDR EQUIVALENT)]                                         
  ┌─────────────────────────────────────────────────────────────────────────────────┐                 
  │  Kelasagara Cloud Run Backend (Node.js / TypeScript)                            │                 
  │  - /api/biometrics/challenge (Single-use server nonces, TTL 120s)               │                 
  │  - /api/biometrics/enroll & /verify (Authoritative Matching Engine)             │                 
  │  - /api/biometrics/cross-account-check (1:N Duplicate Screening)                │                 
  │  - OpenCV Zoo SFace ONNX Runtime (MobileFaceNet + Sigmoid Loss, Apache 2.0)     │                 
  │  - InMemoryBiometricIndex (High-throughput RAM 1:N deduplication)               │                 
  │  - AuditService (Tamper-evident hash-chained audit logging)                     │                 
  └──────────────────────────────────────┬──────────────────────────────────────────┘                 
                                         │ Cloud KMS Envelope Encryption                              
                                         ▼                                                            
  [TIER 4: PROTECTED BIOMETRIC VAULT & PERSISTENCE]                                                   
  ┌─────────────────────────────────────────────────────────────────────────────────┐                 
  │  Cloud Firestore biometric_vault & biometric_audit_logs                         │                 
  │  - AES-256-GCM Envelope Encryption (DEK rotated via Cloud KMS HSM)              │                 
  │  - Zero cleartext biometric vectors stored on disk                              │                 
  │  - Strict Firestore Security Rules: write restricted to backend Admin SDK       │                 
  └─────────────────────────────────────────────────────────────────────────────────┘                 
```

---

## 2. Component Taxonomy & Responsibilities

| Tier | Component File | Key Class / Method | Technical Responsibility |
| :--- | :--- | :--- | :--- |
| **Tier 1** | `lib/screens/auth/face_enrollment_screen.dart` | `_captureAndSave` | Coordinates camera stream, triggers quality analysis, invokes PAD controller. |
| **Tier 1** | `lib/biometrics/advanced_landmark_analyzer.dart` | `analyze(Face)` | Regresses 133 facial landmarks, computes IPD, Euler angles, eye symmetry, and mouth neutrality per ISO 29794-5. |
| **Tier 1** | `lib/biometrics/iso30107_pad_controller.dart` | `processFrame` | Enforces Soukupová-Čech EAR kinematic blink state machine and Pech-Pacheco Laplacian texture bounds. |
| **Tier 1** | `lib/biometrics/landmark_embedding.dart` | `extract(Face)` | Umeyama Procrustes canonical alignment + Whitened Procrustes Gaussian Orthogonal Linear Projection onto $\mathbb{S}^{127}$. |
| **Tier 1** | `lib/biometrics/integrity_request.dart` | `buildPadBoundRequestHash` | Aadhaar WADH equivalent: cryptographically binds UID, nonce, frame digest, $\sigma^2_L$, and IPD into SHA-256. |
| **Tier 2** | `lib/services/biometric_service.dart` | `enrollBiometric` | Manages challenge nonce acquisition, API dispatch, client-side fallback 1:N verification. |
| **Tier 2** | `lib/widgets/duplicate_detected_sheet.dart` | `DuplicateDetectedSheet` | Displays masked duplicate account guidance (`KLS-xK9***wXy-7890`) with zero PII leakage per DPDPA §8(3). |
| **Tier 2** | `lib/widgets/face_reenroll_tile.dart` | `FaceReEnrollTile` | Enables legitimate workers to update templates (haircut, glasses) after step-up blink authentication. |
| **Tier 3** | `backend/src/routes/face_routes.ts` | `POST /enroll` | Validates nonces, authenticates Firebase JWT, executes SFace ONNX inference, dispatches to index. |
| **Tier 3** | `backend/src/services/in_memory_biometric_index.ts` | `findTopK` | Sub-millisecond 1:N in-memory linear cosine scanner across gallery. |
| **Tier 3** | `backend/src/services/biometric_matching.ts` | `cosineSimilarity` | Evaluates unit hypersphere dot product $\langle \mathbf{a}, \mathbf{b} angle$. |
| **Tier 4** | `backend/src/services/firestore_biometric_repository.ts` | `saveEncryptedTemplate` | Seals template with AES-256-GCM envelope, writes to `biometric_vault`, logs event to audit ledger. |

---

## 3. Cryptographic Envelope & Key Management Hierarchy

To ensure strict ISO/IEC 24745 template protection:
1. **Master Key (KEK):** Stored inside Google Cloud KMS, backed by FIPS 140-2 Level 3 Hardware Security Modules (HSM).
2. **Data Encryption Key (DEK):** Generated cryptographically per-write (`crypto.randomBytes(32)`).
3. **Sealed Envelope:** The template vector is encrypted using AES-256-GCM with a 96-bit random IV and 128-bit authentication tag:
   $$	ext{Ciphertext} = 	ext{AES-256-GCM}(	ext{DEK}, 	ext{IV}, \mathbf{e}_{	ext{template}}, 	ext{AAD})$$
   where AAD binds document metadata (`uid`, `modelVersion`, `enrolledAt`).
4. **Key Rotation:** Cloud KMS rotates KEK annually without requiring database re-encryption.
