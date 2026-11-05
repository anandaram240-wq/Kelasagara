# KELASAGARA BIOMETRIC ENGINE V8.0
# Biometric Threat Model & Security Architecture
## Exhaustive Threat Modeling, ISO/IEC 19792 Biometric Attack Points, STRIDE Analysis, and Residual Risk Evaluation

**Document ID:** `DOC-THREAT-V8-01`  
**System:** Kelasagara Biometric Platform  
**Standards:** ISO/IEC 19792:2009, ISO/IEC 30107-3:2023, ISO/IEC 24745:2022, DPDPA 2023  
**Classification:** Confidential Security Engineering Specification  
**Version:** 8.0.0-PROD  
**Date:** 2026-10-22  

---

## 1. Executive Summary & Attack Surface Scope

The Kelasagara Biometric Platform enforces identity assurance and one-to-many fraud prevention across a distributed marketplace of workers and hirers. The system handles sensitive personal identifiers and biometric templates under the jurisdiction of the Indian **Digital Personal Data Protection Act, 2023 (DPDPA)**.

Because mobile client devices (Android smartphones) operate within an untrusted adversary-controlled environment, security cannot be guaranteed by client-side assertions alone. This threat model defines:
1. The seven core biometric and cryptographic assets.
2. The four formal trust boundaries.
3. An exhaustive attack tree mapped against all **8 ISO/IEC 19792 biometric system attack points**.
4. The quantitative risk scoring matrix before and after mitigations.
5. The specific architectural and cryptographic controls that guarantee fail-closed security.

---

## 2. Protected Biometric Assets

| Asset ID | Asset Name | Form & Representation | Sensitivity Level | Impact of Compromise |
| :--- | :--- | :--- | :--- | :--- |
| **A-01** | **Raw Camera Sensor Imagery** | YUV_420_888 / RGB byte buffers in RAM | Critical / PII | Permanent biometric compromise; adversary can synthesize deepfakes or replay face across third-party platforms. |
| **A-02** | **Dense Facial Coordinates** | 513 3D landmark points ($[x, y, z]$) | High | Reconstruction of facial geometry; potential biological tracking across systems. |
| **A-03** | **Biometric Embeddings** | 128-D L2-normalized float vectors ($\mathbb{S}^{127}$) | Critical | Sybil identity creation, duplicate detection bypass, cross-service template inversion. |
| **A-04** | **Identity Binding Record** | Mapping of Firebase `uid` $\leftrightarrow$ Template $\leftrightarrow$ Phone | Critical | Account takeover, credential stuffing, DPDPA regulatory liability. |
| **A-05** | **Cryptographic Key Material** | Google Cloud KMS Master KEKs & Ephemeral DEKs | Systemic | Total vault decryption; wholesale loss of platform biometric confidentiality. |
| **A-06** | **Session Challenges & Nonces** | Cryptographic 256-bit random server nonces | High | Presentation replay attacks, synthetic payload injection. |
| **A-07** | **Authoritative Audit Ledger** | Immutable Firestore / BigQuery event logs | Moderate | Undetected fraud collusion, loss of non-repudiation during labor dispute arbitration. |

---

## 3. Trust Boundaries & Data Flow Diagram

```
+----------------------------------------------------------------------------------------------------+
|                               UNTRUSTED CLIENT DOMAIN (Mobile Device)                              |
|                                                                                                    |
|  [Camera Sensor] --(YUV)--> [CameraX Driver] --(Raw Frame)--> [App Volatile RAM]                  |
|                                                                    |                               |
|                                                     +--------------+--------------+                |
|                                                     |                             |                |
|                                                     v                             v                |
|                                            [ML Kit FaceDetector]        [C++ Laplacian Kernel]     |
|                                            (513 Geometry Pts)           (Sharpness / Texture σ²L)  |
|                                                     |                             |                |
|                                                     +--------------+--------------+                |
|                                                                    |                               |
|                                                                    v                               |
|                                                     [LandmarkEmbedding v3 RFF]                     |
|                                                     (128-D Unit Hypersphere Vector)                |
|                                                                    |                               |
|                                                                    v                               |
|                                                    [HMAC-SHA256 WADH Signature]                    |
|                                                    (Blinks + σ²L + Digest + Nonce)                 |
+--------------------------------------------------------------------+-------------------------------+
                                                                     |
                    === TRUST BOUNDARY 1: Public Network (TLS 1.3 / Certificate Pinning) ===
                                                                     |
                                                                     v
+----------------------------------------------------------------------------------------------------+
|                                  TRUSTED BACKEND DOMAIN (Cloud Run API)                            |
|                                                                                                    |
|  [Reverse Proxy & Cloud Armor] --> [Rate Limiter: 60 req/min] --> [Firebase Token Authenticator]   |
|                                                                             |                      |
|                                                     +-----------------------+                      |
|                                                     |                                              |
|                                                     v                                              |
|                                      [Nonce / Challenge Verifier]                                  |
|                                      - Verify Nonce Single-Use (Redis / Memory)                    |
|                                      - Check Expiration (TTL = 300s)                               |
|                                                     |                                              |
|                                                     v                                              |
|                                      [Biometric Matching Service]                                  |
|                                      - Fast RAM Index: InMemoryBiometricIndex                      |
|                                      - 1:N Linear Deduplication Scan                               |
|                                      - Cosine Similarity >= 0.74 Interception                      |
|                                      - DPDPA PII Masking: KLS-xK9***wXy-7890                       |
+-----------------------------------------------------+----------------------------------------------+
                                                      |
                  === TRUST BOUNDARY 2: Cloud VPC & IAM Role-Based Access Control ===
                                                      |
                                                      v
+----------------------------------------------------------------------------------------------------+
|                                  SECURE STORAGE DOMAIN (GCP KMS & Firestore)                       |
|                                                                                                    |
|  [Google Cloud KMS] <--(Wrapped DEK)--> [AES-256-GCM Envelope Encryption Engine]                   |
|                                                            |                                       |
|                                                            v                                       |
|                                         [Firestore: biometric_vault/{uid}]                         |
|                                         - Encrypted Ciphertext + Auth Tag                          |
|                                         - Length-Prefixed Binary AAD Context                       |
|                                         - Firestore Rules: Locked to Admin SDK Only               |
+----------------------------------------------------------------------------------------------------+
```

---

## 4. ISO/IEC 19792 Biometric Attack Points Analysis

ISO/IEC 19792 defines 8 physical and logical points of vulnerability within biometric systems. The table below documents the attack vectors, vulnerabilities, and mitigations implemented in Kelasagara V8.0.

```
       [Attack Point 1]                      [Attack Point 3]               [Attack Point 5]
              |                                     |                              |
              v                                     v                              v
[User] -> [SENSOR] --(Pt 2)--> [FEATURE EXTRACTOR] --(Pt 4)--> [MATCHER] --(Pt 8)--> [DECISION]
                                                                   ^
                                                                   | (Pt 7)
                                                            [DATABASE / VAULT]
                                                                   ^
                                                                   | (Pt 6)
```

| Attack Point | Attack Class | Detailed Attack Vector | Risk | Architectural Mitigation in Kelasagara V8.0 | Test Verification Reference |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Point 1: Sensor** | Presentation Attack (PAD) | High-resolution 2D photo printout, 4K tablet screen video replay, cut-out photo mask. | **HIGH** | **Active-Passive Hybrid PAD:** Requires spontaneous biological blink kinematics ($EyeOpen \le 0.28 \to \ge 0.58$) combined with C++ Laplacian edge energy check ($\sigma^2_L \in [110, 1850]$). | `test_liveness_injection_bypass.test.js`, `biometric_multi_face_test.dart` |
| **Point 2: Sensor Channel** | Virtual Camera Injection | Malicious APK hook or rooted Android device replacing camera driver stream with synthetic video stream. | **HIGH** | **Cryptographic WADH Binding:** Every capture requires a live challenge nonce from the backend. The nonce is mathematically bound to the frame digest, blink timestamp, and IPD. Replay of recorded streams fails nonce freshness check. | `integrity_request.dart`, backend challenge verifier |
| **Point 3: Feature Extractor** | Code Hooking / Memory Tampering | Frida / Xposed script hooking `LandmarkEmbedding.extract()` in client memory to inject a hardcoded zero-vector or victim vector. | **CRITICAL** | **Server-Side Re-Inference:** For high-assurance enrollment, the client submits the encrypted image burst to the backend. The backend independently extracts facial landmarks and embeddings using OpenCV/SFace, ignoring client-submitted floats. | `Ticket E-03: Server-side landmarks & zero client metadata trust` |
| **Point 4: Feature Transmission** | Man-in-the-Middle (MitM) | Intercepting HTTP payload to substitute another user's biometric vector. | **HIGH** | **Transport Security & Signature:** Enforces TLS 1.3 with certificate pinning. Payloads include HMAC-SHA256 request signatures incorporating caller Firebase ID token and server nonce. | `security_hardening.test.js` |
| **Point 5: Matcher Override** | Threshold Mutation / Bypass | Attacker modifies cosine similarity threshold in memory or manipulates RAM index during search. | **CRITICAL** | **Server-Authoritative Matcher:** The matcher runs entirely within isolated Cloud Run node processes. Mutants attempting threshold off-by-one or inverted calibration slopes are killed by mutation tests. | `Stage S3 Mutation Suite (10 mutants killed)` |
| **Point 6: Database / Storage** | Direct Database Write / Extraction | Malicious client attempts direct Firestore read/write to `biometric_vault` to extract templates or inject fake identities. | **CRITICAL** | **Firestore Security Rules Lockdown:** `biometric_vault/{uid}` rules restrict reads and writes exclusively to the backend service account via Firebase Admin SDK. Direct client access returns `PERMISSION_DENIED`. | `firestore.rules` audit, `security_hardening.test.js` |
| **Point 7: Template Retrieval** | Ciphertext Tampering & Downgrade | Intercepting stored ciphertexts to substitute old v1/v2 unencrypted templates or alter AAD context. | **HIGH** | **Length-Prefixed Binary AAD & Version Floors:** Enforces v3 KMS envelope with binary canonical AAD binding (`tenantId + uid + modelVersion`). Downgrades to v1/v2 envelopes are strictly rejected. | `Stage S8: AAD Canonicalization & KMS Envelope Encryption` |
| **Point 8: Decision Channel** | Client Response Forgery | Attacker intercepts HTTP response to flip `isApproved: false` to `true`, bypassing duplicate block. | **HIGH** | **Server-Side Role Transition:** The client UI cannot self-grant access. Platform capabilities (bidding, job acceptance, worker wallet activation) require the backend to set `biometricVerified: true` on the worker Firestore document. | `client_biometric_integration_test.dart` |

---

## 5. Specific Threat Scenario: Network Fallback & Timeout Bypass

### 5.1 The Threat Vector
A sophisticated attacker registers a duplicate account. When the app begins the 1:N deduplication scan, the attacker enables Airplane Mode or terminates the network socket, hoping the client software defaults to an "Offline Mode / Assume Valid" posture.

### 5.2 The Kelasagara Fail-Closed Defense
Kelasagara enforces a strict **Fail-Closed Architecture**:
1. If the network call times out ($> 8\text{ seconds}$) or returns HTTP 5xx:
   - The client transitions to `BiometricStatus.technicalFailureRetry`.
   - The user account is set to `isApproved: false` and `pendingReview: true`.
   - **No worker account is activated without a positive server-authoritative green verdict.**
2. Offline enrollment is strictly prohibited by platform security policy.
3. Every network failure triggers an auditable retry state machine with exponential backoff and jitter, preventing denial-of-service against the backend.

---

## 6. Quantitative Threat Matrix & Risk Scoring

Scoring Methodology: Common Vulnerability Scoring System (CVSS v3.1) Base Score mapping:
- **Likelihood:** Low (1), Medium (2), High (3)
- **Impact:** Low (1), Medium (2), Critical (3)
- **Risk Score:** $\text{Likelihood} \times \text{Impact} \in [1, 9]$ (1–3: Low, 4–6: Medium, 7–9: Critical)

| Threat ID | Threat Description | Initial Likelihood | Initial Impact | Initial Risk | Implemented Control | Residual Likelihood | Residual Impact | Residual Risk | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **TH-01** | 2D Print Photo / Screen Replay Spoof | High (3) | High (3) | **CRITICAL (9)** | Active blink state machine + C++ Laplacian texture variance. | Low (1) | Medium (2) | **LOW (2)** | **MITIGATED** |
| **TH-02** | Virtual Camera Stream Injection | Medium (2) | Critical (3) | **HIGH (6)** | Cryptographic WADH nonce binding + device integrity check. | Low (1) | High (3) | **LOW (3)** | **MITIGATED** |
| **TH-03** | False Duplicate Collision (Rama vs Kiran) | High (3) | Critical (3) | **CRITICAL (9)** | Whitened Random Fourier Features ($\sigma=4.2$) replacing legacy harmonic DC offset. | Low (1) | Low (1) | **LOW (1)** | **RESOLVED** |
| **TH-04** | Client-Side 1:N Bypass via Network Drop | High (3) | High (3) | **CRITICAL (9)** | Fail-closed state machine; worker activation gated on server-side Firestore claim. | Low (1) | Low (1) | **LOW (1)** | **MITIGATED** |
| **TH-05** | Unauthorized Firestore Template Harvesting | Medium (2) | Critical (3) | **HIGH (6)** | Firestore security rules lock `biometric_vault` to backend Admin SDK only. | Low (1) | Critical (3) | **LOW (3)** | **MITIGATED** |
| **TH-06** | Stored Template Inversion Attack | Low (1) | Critical (3) | **MEDIUM (3)** | Cloud KMS AES-256-GCM envelope encryption + irreversible RFF projection. | Low (1) | Low (1) | **LOW (1)** | **MITIGATED** |
| **TH-07** | Cross-Account PII Leakage on Duplicate Detection | Medium (2) | High (3) | **HIGH (6)** | Masked format (`KLS-xK9***wXy-7890`); zero raw names or unmasked phone numbers transmitted. | Low (1) | Low (1) | **LOW (1)** | **RESOLVED** |
| **TH-08** | Incompatible Model Template Comparison | Medium (2) | High (3) | **HIGH (6)** | Strict model version tagging (`modelVersion`); cross-version comparison throws immediate error. | Low (1) | Low (1) | **LOW (1)** | **MITIGATED** |
| **TH-09** | Replay of Stolen Session Nonce | High (3) | High (3) | **CRITICAL (9)** | Nonce single-use enforcement in Redis/RAM with 300s TTL; instant revocation upon consumption. | Low (1) | Low (1) | **LOW (1)** | **MITIGATED** |
| **TH-10** | Continuous Biometric Score Leakage to Attackers | Medium (2) | Medium (2) | **MEDIUM (4)** | API returns boolean verdict and banded percentage only; raw continuous floating-point scores withheld. | Low (1) | Low (1) | **LOW (1)** | **MITIGATED** |

---

## 7. Residual Risks & Operational Boundaries

Despite comprehensive architectural hardening, the following residual risks cannot be eliminated by software alone and require operational monitoring:

1. **Physical Silicone 3D Mask Attacks (Level 3 PAD):**
   A high-budget adversary employing custom-sculpted, medical-grade silicone prosthetic masks fitted to the wearer's periorbital musculature could theoretically blink naturally while presenting a false face.
   *Residual Risk Rating:* **LOW**. The economic incentive for a blue-collar worker or gig-economy participant does not justify a \$5,000 custom prosthetic mask.
2. **Identical Twin Verification Ambiguity:**
   Monovular identical twins possess indistinguishable facial bone geometry and high neural embedding similarity ($\sim 0.88 - 0.94$).
   *Mitigation:* Platform terms require workers claiming twin identity conflicts to undergo secondary manual document verification (Aadhaar Offline XML / PAN / Driving License) administered by platform operations.
3. **Severe Facial Trauma / Facial Surgery:**
   Workers suffering severe burns, industrial accidents, or facial surgery will experience True Accept Rate degradation.
   *Mitigation:* Profile screen provides a secure **"Re-enroll Face ID"** option protected by SMS OTP re-authentication and manual supervisory approval.
