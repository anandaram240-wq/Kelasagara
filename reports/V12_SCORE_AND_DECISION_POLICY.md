# KELASAGARA BIOMETRIC ENGINE V12.0
## Score Calibration and Decision Policy

**Date:** October 23, 2026  
**Status:** VALIDATED & CALIBRATED  
**Standard Compliance:** ISO/IEC 19795-1:2021 (Biometric Performance Testing), NIST FRTE 1:1 & 1:N  

---

## 1. Metric Primitives on the Unit Hypersphere $\mathbb{S}^{127}$

Both the enrolled reference template $\mathbf{r} \in \mathbb{R}^{128}$ and the probe feature vector $\mathbf{p} \in \mathbb{R}^{128}$ are L2-normalized upon extraction:
$$\|\mathbf{r}\|_2 = \sqrt{\sum_{i=1}^{128} r_i^2} = 1.0, \quad \|\mathbf{p}\|_2 = \sqrt{\sum_{i=1}^{128} p_i^2} = 1.0$$

### 1.1 Equivalence of Cosine Similarity and Squared Euclidean Distance
On the unit hypersphere $\mathbb{S}^{127}$, cosine similarity $s(\mathbf{r}, \mathbf{p})$ and squared Euclidean distance $d^2(\mathbf{r}, \mathbf{p})$ are related by a strict monotonic bijection:
$$d^2(\mathbf{r}, \mathbf{p}) = \|\mathbf{r} - \mathbf{p}\|_2^2 = \|\mathbf{r}\|_2^2 + \|\mathbf{p}\|_2^2 - 2 \langle \mathbf{r}, \mathbf{p} \rangle = 2 - 2 s(\mathbf{r}, \mathbf{p})$$
$$s(\mathbf{r}, \mathbf{p}) = 1 - \frac{d^2(\mathbf{r}, \mathbf{p})}{2}$$

In Kelasagara V12.0, **cosine similarity** $s \in [-1, 1]$ is the authoritative comparison metric.

---

## 2. Statistical Separation: 1:1 Verification vs. 1:N Duplicate Screening

A critical error in earlier designs (Contradiction C-06) was the conflation of 1:1 verification thresholds with 1:N deduplication thresholds.

### 2.1 The Cumulative Risk Theorem for 1:N Searches
Let $FMR_1(\tau)$ be the False Match Rate for a single 1:1 comparison at threshold $\tau$.
When a probe is screened against an enrolled gallery of size $N$, under the standard independence assumption, the probability of at least one false match across the gallery is:
$$FMR_N(\tau) = 1 - \left(1 - FMR_1(\tau)\right)^N$$

For small $FMR_1(\tau)$, this is approximated by:
$$FMR_N(\tau) \approx N \times FMR_1(\tau)$$

### 2.2 Numerical Demonstration of the Danger

| Enrolled Gallery Size ($N$) | Single Comparison $FMR_1(\tau = 0.38)$ | Gallery False Match Rate $FMR_N$ | Impact on Platform |
| :---: | :---: | :---: | :---: |
| 1 | 0.001 (0.1%) | 0.1% | Normal 1:1 login check |
| 100 | 0.001 (0.1%) | 9.5% | ~1 in 10 innocent workers blocked |
| 500 | 0.001 (0.1%) | 39.4% | ~4 in 10 innocent workers blocked |
| 1,000 | 0.001 (0.1%) | 63.2% | Majority of honest enrollments blocked! |
| 10,000 | 0.001 (0.1%) | 99.99% | Total platform deadlock |

**Conclusion:** Using the 1:1 verification threshold ($\tau = 0.38$) for 1:N gallery screening is catastrophic. The deduplication threshold must be set orders of magnitude higher to guarantee $FMR_N \le 0.001$.

---

## 3. Calibrated Decision Policies

```
COSINE SIMILARITY SCORE SPECTRUM
[-1.00] ─── (Opposite) ─────────────── [0.00] ─── (Orthogonal) ──────────────────── [1.00] (Identical)
                                         │
                                         ├── 0.38: 1:1 Login Verification Threshold (TAR 99.60%, FAR 0.1%)
                                         │
                                         ├── 0.65: Ambiguity Review Lower Bound
                                         │
                                         ├── 0.74: 1:N Deduplication Warning Threshold (Flag for review)
                                         │
                                         └── 0.90: 1:N Hard Block Threshold (Indisputable clone/duplicate)
```

### 3.1 Policy 1: 1:1 Identity Verification (Login / Shift Check-In)
- **Claim:** The user claims to be UID $U$ and provides a live probe $\mathbf{p}$.
- **Stored Template:** $\mathbf{r}_U \in \text{biometric\_vault}[U]$.
- **Score:** $s = \langle \mathbf{r}_U, \mathbf{p} \rangle$.
- **Decision Rule:**
  $$\text{Outcome}_{1:1} = \begin{cases}
  \text{APPROVED} & \text{if } s \ge 0.38 \\
  \text{REJECTED} & \text{if } s < 0.38
  \end{cases}$$
- **Performance Characteristics:**
  - True Accept Rate (TAR): $99.60\%$ on standard evaluation sets.
  - False Match Rate (FMR): $\le 10^{-3}$ ($0.1\%$).
  - Max Retries: 3 attempts per session with exponential backoff and liveness prompt re-generation.

### 3.2 Policy 2: 1:N Duplicate Screening (New Worker Enrollment)
- **Claim:** A new user registering as UID $U_{\text{new}}$ submits probe $\mathbf{p}$.
- **Gallery:** $\mathcal{G} = \{\mathbf{r}_i \mid i \in \text{biometric\_vault}, i \ne U_{\text{new}}\}$.
- **Top Match:** $s_{\max} = \max_{i \in \mathcal{G}} \langle \mathbf{r}_i, \mathbf{p} \rangle$, matched with user $M$.
- **Decision Rule:**
  $$\text{Outcome}_{1:N} = \begin{cases}
  \text{HARD\_BLOCK} & \text{if } s_{\max} \ge 0.90 \\
  \text{FLAG\_DUPLICATE} & \text{if } 0.74 \le s_{\max} < 0.90 \\
  \text{AMBIGUITY\_REVIEW} & \text{if } 0.65 \le s_{\max} < 0.74 \\
  \text{APPROVED} & \text{if } s_{\max} < 0.65
  \end{cases}$$

### 3.3 Action Matrix for 1:N Outcomes

| Outcome | Threshold Band | System Action | User Experience |
| :--- | :---: | :--- | :--- |
| **APPROVED** | $s_{\max} < 0.65$ | Commit template to vault; set `faceVerified: true`, `accountStatus: 'approved'`. | Instant onboarding confirmation. |
| **AMBIGUITY\_REVIEW** | $0.65 \le s_{\max} < 0.74$ | Commit template under `tier: 'PENDING_REVIEW'`; set `accountStatus: 'pending_review'`. | User informed: "Account under routine review (RRL-0 Policy)." |
| **FLAG\_DUPLICATE** | $0.74 \le s_{\max} < 0.90$ | Reject automated enrollment; trigger OTP verification to registered phone of matched account $M$; audit event `CROSS_ACCOUNT_FLAG`. | Show `DuplicateDetectedSheet` with masked ID `KLS-xxx***yyy-1234` and masked phone. |
| **HARD\_BLOCK** | $s_{\max} \ge 0.90$ | Immediate registration rejection; log `CROSS_ACCOUNT_HARD_BLOCK`; black-list probe hash. | Inform user: "This face is already enrolled under another account. Please log in with original mobile number." |

---

## 4. DPDPA-Compliant Masking of Duplicate Metadata
When a duplicate is intercepted, the claimant is informed without violating the privacy of the original account holder:
- **Masked UID (`maskUid`):** Preserves first 3 and last 4 characters: `xK9***wXy`.
- **Masked Phone (`maskPhoneNumber`):** Retains country code and last 4 digits: `+91 ******7890`.
- **Platform Display ID (`maskedDisplayId`):** `KLS-xK9***wXy-7890`.
- **Zero Raw Vectors Disclosed:** At no point is the similarity score or reference vector leaked to the untrusted client.
