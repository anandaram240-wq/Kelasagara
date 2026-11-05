# KELASAGARA BIOMETRIC ENGINE V8.0
# Technical Standards & Benchmark Crosswalk Analysis
## Architectural Alignment across ISO/IEC, NIST, UIDAI, and Indian Data Protection Law

**Document ID:** `DOC-CROSSWALK-V8-01`  
**System:** Kelasagara Biometric Platform  
**Target Architecture:** Dual-Layer Client-Authoritative Landmark + Server-Authoritative Deep Biometrics  
**Classification:** Technical & Regulatory Standards Compliance Specification  
**Version:** 8.0.0-PROD  
**Date:** 2026-10-22  

---

## 1. Executive Standards Taxonomy

Biometric systems deployed within commercial, multi-sided labour marketplaces operate under an overlapping matrix of international technical standards, empirical benchmark evaluations, national identity technical guidelines, and statutory personal data protection mandates. 

The table below establishes the normative and informative standards crosswalk for the Kelasagara Biometric Engine V8.0.

```
+----------------------------------------------------------------------------------------------------+
|                                    STATUTORY DATA PROTECTION MANDATES                              |
|                         Digital Personal Data Protection Act, 2023 (DPDPA)                         |
|                         Digital Personal Data Protection Rules, 2025                              |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                         +------------------------+-----------------------+
                         |                                                |
                         v                                                v
+------------------------------------------------+ +-------------------------------------------------+
|          ISO/IEC SCIENTIFIC STANDARDS          | |          NIST EVALUATION BENCHMARKS             |
|  - ISO/IEC 39794-5:2024 (Data Interchange)     | |  - NIST SP 800-63B-4 (Digital Identity Auth)    |
|  - ISO/IEC 29794-5:2025 (OFIQ Quality)         | |  - NIST FRVT / FATE 1:1 & 1:N Identification    |
|  - ISO/IEC 30107-3:2023 (Liveness / PAD)       | |  - NIST FRVT Part 3 (Demographic Effects)       |
|  - ISO/IEC 24745:2022 (Template Protection)    | |  - NIST FATE Part 10 (Software PAD Testing)     |
|  - ISO/IEC 19795-1:2021 (Evaluation Metrics)   | +-------------------------------------------------+
+------------------------------------------------+
                         |
                         v
+----------------------------------------------------------------------------------------------------+
|                                   NATIONAL IDENTITY ARCHITECTURE                                   |
|                       UIDAI Face RD Service v2.0 Specifications & Technical FAQs                    |
|             (Separate 1:1 Authentication vs 1:N Central De-Duplication CIDR Architecture)           |
+----------------------------------------------------------------------------------------------------+
```

---

## 2. Normative Standard Mapping Matrix

| Standard / Benchmark | Publishing Body | Domain & Scope | Kelasagara Implementation Component | Conformance Status | Technical Gap / Practical Limitation |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **ISO/IEC 39794-5:2024** | ISO/IEC JTC 1/SC 37 | Extensible face image data interchange format, frontal pose constraints, header metadata. | `advanced_landmark_analyzer.dart` & `biometric_matching.ts` | **CONFORMANT (Header & Metadata)** | Full CBEFF XML binary container omitted to minimize mobile payload footprint; JSON schema parity maintained. |
| **ISO/IEC 29794-5:2025 (OFIQ)** | ISO/IEC JTC 1/SC 37 / BSI | Open Source Face Image Quality (OFIQ) unified quality metrics (IPD, pose, sharpness, illumination). | `FaceQualityMetrics` & C++ Laplacian kernel (`pad_controller.cpp`) | **PARTIALLY CONFORMANT** | Employs calibrated native 2D Laplacian ($\sigma^2_L \ge 110$) and IPD ($\ge 90\text{ px}$); full 17-component neural OFIQ requires 120MB weights, infeasible on entry-level Android. |
| **ISO/IEC 30107-3:2023** | ISO/IEC JTC 1/SC 37 | Biometric presentation attack detection (PAD): testing, metrics (APCER, BPCER), attack species. | `iso30107_pad_controller.dart`, `pad_controller.cpp`, `pad_inference.dart` | **CONFORMANT (Level 1 Presentation Attacks)** | Protects against 2D paper print, digital screen replay, and video playback via multi-frame blink kinematics + texture variance + WADH binding. |
| **ISO/IEC 24745:2022** | ISO/IEC JTC 1/SC 27 | Biometric information protection: irreversibility, unlinkability, confidentiality, renewability. | Google Cloud KMS envelope encryption (`aes-256-gcm`), PBKDF2 salt derivation, zero-out raw pixels. | **CONFORMANT (Systemic / Cryptographic)** | Full cancelable BioHashing avoided due to irreversible 18-24% degradation in True Accept Rates; KMS envelope encryption provides standard cryptographic confidentiality. |
| **ISO/IEC 19795-1:2021** | ISO/IEC JTC 1/SC 37 | Biometric performance testing and reporting: FMR, FNMR, FPIR, FNIR, failure-to-acquire (FTA). | `biometric_whitened_embedding_test.dart` & test harness | **CONFORMANT** | Performance reported strictly through empirical FMR/FNMR distributions; marketing percentages prohibited. |
| **NIST SP 800-63B-4** | NIST | Digital Identity Guidelines: Authenticator Assurance Level 3 (AAL3), biometric rate limits, fixed thresholds. | Backend token exchange, session nonce, strict $\text{FAR} \le 10^{-4}$ threshold. | **ALIGNED (Informative)** | Informative security guideline; AAL2/AAL3 rate-limiting enforced on registration and login endpoints. |
| **NIST FRVT / FATE** | NIST | Independent, empirical 1:1 verification, 1:N identification, and demographic variance evaluation. | Model selection baseline (SFace & MobileFaceNet benchmarks). | **ALIGNED (Informative)** | Evaluates candidate models against NIST benchmark rankings (SFace ranked top-tier compact model). |
| **UIDAI Face RD v2.0** | UIDAI | Face Registered Device specification: WADH cryptographic request binding, PID block encryption. | `integrity_request.dart` (`buildPadBoundRequestHash`) & server matching service | **ARCHITECTURALLY ALIGNED** | Implements cryptographic binding (Blink verdict + $\sigma^2_L$ + SHA-256 digest + Nonce); does NOT impersonate or claim access to UIDAI CIDR. |
| **DPDPA 2023 / Rules 2025** | Government of India | Digital Personal Data Protection Act: lawful basis, consent notices, purpose limitation, right to erasure. | Bilingual notice UI, zero-pixel retention, KMS encryption, audit logging, deletion workflows. | **STATUTORILY COMPLIANT** | Raw camera frames zeroed in volatile memory immediately post-inference; biometric templates erasable via profile screen. |

---

## 3. Deep Analysis of Standard Conformance & Technical Boundaries

### 3.1 ISO/IEC 39794-5:2024 vs ISO/IEC 19794-5:2011 (Data Interchange & Pose Constraints)
ISO/IEC 39794-5:2024 replaces legacy 19794-5 formats, defining extensible XML/CBEFF representations for face image interchange.
- **Pose Angle Strictness:** Mandates $|Yaw| \le 5^\circ$, $|Pitch| \le 5^\circ$, and $|Roll| \le 8^\circ$ for enrollment quality.
- **Kelasagara Implementation:** `AdvancedLandmarkAnalyzer.analyze()` dynamically measures geometric yaw from subnasale offset relative to interpupillary midpoint:
  $$\text{Yaw}_{\text{geom}} = \frac{X_{\text{nose}} - X_{\text{eye\_mid}}}{\|X_{\text{eye\_right}} - X_{\text{eye\_left}}\|} \times 30.0^\circ$$
  Frames exceeding these thresholds are rejected with real-time UI guidance in Kannada and English before embedding extraction.
- **Boundary:** To avoid unnecessary 15KB XML overhead on low-bandwidth 2G/3G connections across rural Karnataka, the client encodes metadata in strict canonical JSON conforming to ISO 39794-5 parameter semantics.

### 3.2 ISO/IEC 29794-5:2025 (Face Image Quality & OFIQ Principles)
ISO/IEC 29794-5:2025 establishes standardized algorithms for predicting face image utility in automated recognition systems.
- **Interpupillary Distance (IPD):** Mandates a strict floor of $\text{IPD} \ge 90\text{ pixels}$ for high-assurance registration.
- **Kelasagara Implementation:** Enforces $\text{IPD} \ge 90\text{ px}$ in `client_biometric_integration_test.dart` and `iso30107_pad_controller.dart`. Low-resolution captures trigger `'ಮುಖ ತುಂಬಾ ದೂರ — Move closer'`.
- **Sharpness Metric:** Evaluates edge energy using a 2D Laplacian kernel:
  $$L = \begin{bmatrix} 0 & 1 & 0 \\ 1 & -4 & 1 \\ 0 & 1 & 0 \end{bmatrix}, \quad \sigma^2_L = \frac{1}{N} \sum_{x,y} \left(I * L - \mu_L\right)^2$$
  Threshold bounds: $\sigma^2_L \in [110, 1850]$ to prevent both motion blur and high-frequency moiré display artifacts.

### 3.3 ISO/IEC 30107-3:2023 (Presentation Attack Detection & Liveness)
Defines Attack Presentation Classification Error Rate (APCER) and Bona Fide Presentation Classification Error Rate (BPCER).
- **APCER Target:** $\le 8.0\%$ at $\text{BPCER} \le 5.0\%$ under Level 1 2D presentation attacks (printed paper, electronic screen re-presentation).
- **Kelasagara Multi-Modal Defense:**
  1. *Kinematic Challenge:* Requires physiological eye-closure transition ($EyeOpen \le 0.28$) followed by recovery ($EyeOpen \ge 0.58$) across at least 5 consecutive frames.
  2. *Frequency & Texture Variance:* Evaluates micro-texture variance via native C++ Laplacian analysis.
  3. *Zero-Knowledge Nonce Binding:* Incorporates server-issued cryptographic nonces into the request payload hash, preventing replay of previously captured bona fide video streams.

### 3.4 ISO/IEC 24745:2022 (Biometric Information Protection & Template Irreversibility)
ISO/IEC 24745 establishes four core principles for biometric template security:
1. **Irreversibility:** It must be computationally infeasible to reconstruct the original biometric sample (face image) from the stored template.
2. **Unlinkability:** Templates generated from the same face across different applications or databases must not be cross-matchable.
3. **Renewability / Revocability:** Compromised templates must be revocable and replaceable with newly seeded templates.
4. **Confidentiality & Integrity:** Cryptographic sealing must prevent unauthorized alteration or inspection.

- **Algorithmic Evaluation:**
  - *Mathematical Irreversibility:* RFF Whitened v3 projection reduces 513 coordinates to 128 hypersphere dimensions. Reconstruction of exact face topography from 128 Fourier coefficients is strictly an underdetermined inverse problem ($128 \ll 1026$ equations).
  - *Cryptographic Storage Protection:* Stored templates in `biometric_vault/{uid}` are envelope-encrypted using Google Cloud KMS AES-256-GCM. Unauthenticated clients receive encrypted ciphertexts (`encryptedVector`, `iv`, `wrappedDek`).

### 3.5 UIDAI Face RD Service Architectural Alignment (Informative)
- **Separation of 1:1 Authentication vs 1:N De-Duplication:**
  Aadhaar uses two distinct subsystems:
  - *Face RD (Registered Device):* Edge client performing 1:1 authentication against an existing identity claim ($UID \to \text{Claimed Profile}$).
  - *CIDR Central Matching Engine:* Backend cluster performing 1:N de-duplication against 1.4 billion identities.
- **Kelasagara Architectural Parity:**
  - Kelasagara strictly separates **1:1 Login Verification** (local/server comparison against the user's registered template) from **1:N Fraud Deduplication** (server-authoritative scan across the platform's multi-account gallery).
  - Cryptographic WADH-style binding binds device state, nonce, and quality metrics directly into the payload hash.
  - **Explicit Non-Equivalence Statement:** Kelasagara is an independent marketplace and does NOT access, query, or impersonate UIDAI systems or hold Aadhaar numbers.

---

## 4. Benchmark Crosswalk: Academic Baselines vs Operational Deployment

| Benchmark / Dataset | Primary Task | Metric Evaluated | Literature SOTA (ArcFace/AdaFace) | Kelasagara Operational Target | Operational Difference Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **LFW (Labeled Faces in the Wild)** | 1:1 Verification | Accuracy (%) | 99.83% | $\ge 98.5\%$ | LFW pairs are highly constrained and unrepresentative of rural Indian smartphone cameras, dust, and non-uniform lighting. |
| **CFP-FP (Celebrities in Frontal-Profile)** | Pose Variation | TAR @ FAR=0.1% | 98.85% | N/A (Gate Rejection) | Kelasagara explicitly rejects profile faces via ISO 39794-5 quality gating ($|Yaw| > 5^\circ$). Profile matching is unnecessary. |
| **AgeDB-30** | Age Progression | Accuracy (%) | 98.35% | $\ge 95.0\%$ | Seasonal blue-collar workers experience sun exposure and rapid superficial changes; periodic template re-enrollment supported. |
| **IJB-C (IARPA Janus Benchmark)** | Mixed 1:1 & 1:N | TAR @ $\text{FAR}=10^{-4}$ | 96.00% | $\ge 92.5\%$ (SFace) | Unconstrained surveillance-style IJB-C contains extreme blur; Kelasagara enforces strict capture-stage quality gating. |
| **MegaFace / 1M Gallery** | 1:N Identification | Rank-1 Identification | 98.40% | $\ge 94.0\%$ (Top-3 Recall) | Kelasagara gallery ($N \approx 50,000$ projected) uses exact vector search baseline rather than lossy quantization. |
| **OULU-NPU (Protocol 4)** | Presentation Attack | APCER / BPCER | $1.2\% / 1.8\%$ | $\le 5.0\% / \le 5.0\%$ | OULU Protocol 4 evaluates cross-device and cross-environment PAD generalization. |
| **RFW (Racial Faces in-the-Wild)** | Demographic Disparity | Error Rate Disparity Ratio | $1.8\times - 2.5\times$ | Disparity Ratio $\le 1.3\times$ | Standard models over-index on Caucasian/East-Asian training sets. RFF Whitened v3 uses geometric whitening to eliminate pigmentation bias. |

---

## 5. Verification Checklist & Conformance Sign-Off

- [x] **ISO/IEC 39794-5:2024:** Frontal pose gating ($|Yaw|, |Pitch| \le 5^\circ$) enforced before extraction.
- [x] **ISO/IEC 29794-5:2025:** Interpupillary distance ($\text{IPD} \ge 90\text{ px}$) and edge sharpness validated.
- [x] **ISO/IEC 30107-3:2023:** Kinematic eye-closure state machine verified against presentation attacks.
- [x] **ISO/IEC 24745:2022:** Cryptographic envelope encryption and irreversible Fourier projection.
- [x] **NIST SP 800-63B-4:** Single fixed decision threshold ($\tau = 0.74$) aligned with $\text{FAR} \le 10^{-4}$.
- [x] **DPDPA 2023 §8(3):** Raw pixels flushed from memory; zero unencrypted biometric templates at rest.
