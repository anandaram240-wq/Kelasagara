# V19 Face Accuracy and Threshold Calibration Report

## 1. Mathematical Metric & Score Direction
All biometric comparisons are computed using Cosine Similarity on unit vectors $\mathbf{u}, \mathbf{v} \in \mathbb{S}^{127}$:
$$\text{Sim}(\mathbf{u}, \mathbf{v}) = \mathbf{u} \cdot \mathbf{v} = \sum_{i=1}^{128} u_i v_i \in [-1.0, 1.0]$$
- Higher scores indicate greater facial similarity.
- $1.0$ indicates identical vectors.
- Genuine pair distributions typically range in $[0.45, 0.90]$.
- Impostor pair distributions typically range in $[-0.20, 0.30]$.

## 2. Decision Threshold Hierarchy
The system enforces strict monotonic threshold separation:

$$\tau_{1:1} (0.363) < \tau_{\text{warn}} (0.740) < \tau_{\text{hard}} (0.900)$$

| Threshold Parameter | Value | Decision Boundary | Behavioral Outcome |
|:---|:---:|:---|:---|
| **`verificationThreshold`** | `0.363` | 1:1 Claimed Identity Verification | Match accepted if $S \ge 0.363$; rejected otherwise |
| **`duplicateThreshold`** | `0.740` | 1:N Screening (Advisory Review) | Flagged for review if $S \ge 0.740$; unique if $S < 0.740$ |
| **`hardBlockThreshold`** | `0.900` | 1:N Screening (Hard Interception) | Registration hard-blocked with masked UID hint if $S \ge 0.900$ |

## 3. 1:1 Verification vs 1:N Identification Separation
- **1:1 Verification:** Evaluated under False Match Rate (FMR) and False Non-Match Rate (FNMR).
- **1:N Search:** Evaluated under False Positive Identification Rate (FPIR) and False Negative Identification Rate (FNIR) at gallery size $N$. As $N$ expands, FPIR accumulates:
  $$\text{FPIR}(N) \approx 1 - (1 - \text{FMR})^N$$
  This mathematical reality explains why 1:N duplicate detection demands a significantly higher threshold ($0.74$ vs $0.363$) to prevent false collisions.

## 4. Empirical Evaluation Status: NOT VALIDATED
- **Synthetic Unit Tests:** 230/230 backend automated tests pass, confirming mathematical invariants, bounding logic, and error handling.
- **Real-World Demographic Validation:** **NOT VALIDATED**.
- **Sample Size Constraint:** A test on 50–100 local images cannot establish a $0.1\%$ FMR. Proving $0.1\%$ error bound with 95% confidence requires at least 3,000 independent subject pair trials under the Rule of Three.
- **Production Gate Status:** `productionBiometricCalibrationApproved = false` remains strictly enforced until physical trials on Indian workers are logged and signed off.
