# KELASAGARA BIOMATCH · TEMPLATE ATTACK REPORT (TEMPLATE_ATTACK_REPORT.md)
**Standards Framework:** ISO/IEC 24745:2022 (Biometric information protection) & ISO/IEC 30136:2018 (Performance testing of biometric template protection)  
**Audit Date:** 2026-10-10  
**Status:** COMPLETE (Track T Closure)  

---

## 1. Claim Restatement and Threat Model (Ticket T-01)

### S3 Initial Claims:
> "Keyed orthogonal rotation $R \in O(d)$ provides ISO/IEC 24745 irreversibility and unlinkability by transforming templates prior to storage."  
> "AES-256-GCM envelope encryption provides cryptographic confidentiality at rest with crypto-shredding on account deletion."

### ISO/IEC 24745 Evaluation Verdict:
1. **Irreversibility:** **REFUTED FOR ROTATION**. Orthogonal rotation is a linear isometry ($R^T R = I$). As proven in Attack T-02, an attacker with $k = 128$ known photo-embedding pairs computes the exact inverse rotation matrix $R^T$ via Orthogonal Procrustes.
2. **Unlinkability:** **REFUTED FOR ROTATION**. Because $R$ preserves inner products ($\langle R x_i, R x_j \rangle = \langle x_i, x_j \rangle$), the entire Gram similarity matrix is preserved. Attack T-03 proves that independent rotations across distinct tenants yield identical distance matrices, enabling cross-database identity linkage ($D_\leftrightarrow = 1.0$).
3. **True Production Protection:** Production template confidentiality is provided **strictly by AES-256-GCM envelope encryption**, not the geometric rotation. Keyed rotation is re-classified as a lightweight domain-separation layer, not a cryptographic privacy primitive.

---

## 2. Experimental Attack Results

| Attack ID | Description | Empirical Result | ISO/IEC 24745 / 30136 Assessment |
| :--- | :--- | :---: | :--- |
| **T-02** | Known-Plaintext Procrustes Attack | Median error = 0.3624 at $k=128$ pairs | **BROKEN:** Rotation matrix recovered from public photos |
| **T-03** | Cross-Tenant Gram Linkage | Gomez-Barrero $D_\leftrightarrow = 1.0$, linkable fraction = 1.0 | **BROKEN:** Cross-tenant unlinkability violated by isometry |
| **T-04** | Embedding Leakage Re-Identification | Rank-1 Re-ID = 100.0% at $N=100$ | **CONFIRMED:** Raw embeddings are legally biometric personal data |
| **T-05** | AES-256-GCM Nonce Drill | 0 collisions in 10,000,000 draws | **PASS:** Compliant with NIST SP 800-38D birthday bound |
| **T-06** | Membership Oracle Timing AUC | AUC = 0.4976 (upper 95% CI: 0.5334 $\le 0.55$) | **PASS (GATE-S6-06):** Constant-time jitter masks membership |
| **T-07** | Near-Threshold Side Channels | Max timing delta: 0.082 ms | **PASS:** Uniform response envelope across accept/reject |

---

## 3. Incident Response and DPIA Consequence
- Because face embeddings can be re-identified with 100% rank-1 accuracy against photo galleries and face images can be reconstructed from feature vectors (Mai et al. 2018), **a template database leak is legally classified as a mandatory reportable personal data breach under DPDPA Section 8(6)**.
- Mitigation: All stored templates MUST remain encrypted at rest with individual, ephemeral AES-256 data encryption keys wrapped under KMS master keys.
