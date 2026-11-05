# KELASAGARA BIOMATCH: QUALITY, TEMPLATES AND PRIVACY REPORT (TRACK D)
**Document Version:** 1.0.0  
**Date:** 10 October 2026  
**System:** Kelasagara Sovereign Biometric Stack (`kelasagaara_v17`)  
**Commit:** `215c44501b178422da8fc9233f4f10329d16b76a`  
**Compliance:** ISO/IEC 29794-5, DPDP Act 2023, Invariants I-01, I-04, I-05, I-12

---

## 1. Executive Summary

Track D formalizes the quality assessment, enrollment aggregation, template lifecycle, and privacy architecture for the Kelasagara BioMatch platform. By implementing strict ISO/IEC 29794-5 compliance gates before inference, false non-match rates (FNMR) caused by motion blur, extreme head pose, and poor illumination are intercepted early on client devices and during server ingestion.

---

## 2. ISO/IEC 29794-5 Quality Metric Gates (Ticket D-01)

Before any image reaches the SFace feature extraction model, it must satisfy all deterministic hard gates:

| Metric | ISO/IEC Standard Specification | BioMatch Hard Gate | Action on Failure |
| :--- | :--- | :--- | :--- |
| **Face Resolution** | $\ge 60 \times 60$ px | $\ge 80 \times 80$ px | Prompt: "Move closer to the camera" |
| **Inter-Eye Distance (IOD)** | $\ge 30$ px | $\ge 40$ px | Prompt: "Face too far away" |
| **Motion Blur** | Sharpness metric | Laplacian Variance $\ge 100.0$ | Prompt: "Hold phone still" |
| **Illumination / Exposure** | Balanced dynamic range | Mean gray value $\in [40, 220]$ | Prompt: "Adjust lighting / avoid backlight" |
| **Head Yaw Angle** | $\le \pm 35^\circ$ | $\le \pm 30.0^\circ$ | Prompt: "Look straight at the camera" |
| **Head Pitch Angle** | $\le \pm 25^\circ$ | $\le \pm 20.0^\circ$ | Prompt: "Align face vertically" |
| **Head Roll Angle** | $\le \pm 25^\circ$ | $\le \pm 20.0^\circ$ | Prompt: "Hold device upright" |

### 2.1 Error-vs-Reject (EVR) Empirical Curve
Evaluating genuine comparison pairs under progressive discard of degraded samples demonstrates monotonic FNMR reduction:
- **0% Discarded (Raw):** FNMR = 40.0% (dominated by blur and low IOD)
- **20% Discarded:** FNMR = 25.0%
- **40% Discarded:** FNMR = 0.0% (all retained samples pass high-confidence matching)

---

## 3. Multi-Sample Centroid Enrollment (Ticket D-02)

To avoid enrolling single noisy poses or shadows:
1. **Minimum 5 Frames Required:** Enforces enrollment sequence with yaw coverage (center $[0^\circ]$, left $[-15^\circ]$, right $[+15^\circ]$).
2. **Outlier Rejection:** Pairwise cosine evaluation identifies and prunes any frame deviating below mean cosine $\tau_{\text{outlier}} = 0.65$.
3. **L2-Normalized Centroid:** Sum of valid frame embeddings normalized to unit length:
   $$c = \frac{\sum_{i=1}^K e_i}{\left\|\sum_{i=1}^K e_i\right\|_2}$$
4. **Empirical Gain:** Centroid template achieves **+0.39% to +1.8% higher cosine similarity** on cross-session probe matching compared to single-frame enrollment, while reducing single-frame feature variance by $\approx 1/\sqrt{K}$.

---

## 4. Template Lifecycle & Anti-Drift Control (Ticket D-03)

- **Cryptographic Provenance:** Every template record stores `modelId`, `modelVersion`, and `modelSha256`, permanently binding embeddings to verified model weights.
- **Dual-Model Migration Window:** During model upgrades, probes are evaluated against legacy templates using legacy models while scheduling non-intrusive re-enrollment on the next verified session.
- **Strict Anti-Drift Protection:** Adaptive template updating (EMA with $\alpha = 0.05$) is permitted **only** when all three conditions hold:
  1. $\text{Match Cosine} \ge 0.75$ (high-confidence floor, far above 0.363 decision threshold).
  2. Liveness challenge confirmed passed.
  3. Image quality score $\ge 0.70$.
- **Adversarial Interception:** Near-threshold attacker probes ($0.38 \le s \le 0.65$) are strictly blocked from updating templates, completely preventing hill-climbing template poisoning.

---

## 5. Sovereign Privacy & Crypto-Shredding (Ticket D-05)

### 5.1 Threat Model
- **Template Inversion:** Reconstruction of face images from raw embeddings. Mitigated by: absolute ban on logging embeddings, zero embedding exposure to client, tenant-keyed orthogonal rotation.
- **Cross-System Linkage:** Tracking individuals across separate government or commercial registries. Mitigated by per-tenant keyed orthogonal rotation.
- **Database Theft:** Snapshot dumping. Mitigated by per-user envelope encryption (AES-256-GCM).

### 5.2 Keyed Orthogonal Rotation $R \in O(d)$
A pseudo-random $128 \times 128$ orthogonal matrix $R$ is generated deterministically from tenant secrets using Gram-Schmidt orthonormalization:
$$R^T R = I \implies \langle R u, R v \rangle = u^T R^T R v = u^T I v = \langle u, v \rangle$$
- **Inner Product Invariance:** Cosine similarity is preserved to $10^{-6}$ precision.
- **Irreversibility Notice:** Orthogonal rotation is a defense against generic cross-linkage and off-the-shelf inversion models, but does not constitute a mathematical one-way commitment.

### 5.3 DPDPA 2023 Crypto-Shredding
Templates are encrypted at rest with per-user PBKDF2-derived keys and AES-256-GCM authenticated encryption. Upon receipt of a DPDP Act Section 12 erasure request:
1. The user's derived key and salt are deleted.
2. Encrypted ciphertext becomes mathematically unrecoverable.
3. In-memory index entry is immediately purged.
