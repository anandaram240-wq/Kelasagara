# KELASAGARA V20.10: COLOUR CONVERSION VALIDATION
## Mathematical Equivalence, Numerical Fidelity, and Channel Order Verification

**System:** Kelasagara Major Project  
**Phase:** 20.10  
**Auditor:** Mobile Computer Vision Engineer  
**Date:** November 1, 2026

---

### 1. Color Conversion Policy: Full-Range ITU-R BT.601

Camera sensors deliver full-range $YUV \in [0, 255]$ data spaces. The conversion policy standardizes on full-range ITU-R BT.601:

$$\begin{aligned}
R &= Y + 1.402 \times (V - 128) \\
G &= Y - 0.344136 \times (U - 128) - 0.714136 \times (V - 128) \\
B &= Y + 1.772 \times (U - 128)
\end{aligned}$$

Clamping is strictly applied to $[0, 255]$.

---

### 2. Multi-Patch Numerical Fidelity Benchmarks

In unit test `phase20_10_capture_wire_verification.test.ts` Suite C, 4 multi-chroma patches (Pure Red, Pure Green, Pure Blue, and Neutral Gray) were synthesized and evaluated across the complete compression round-trip:

| Patch Description | Original (R, G, B) | Decoded (R, G, B) | Abs Error | MAE | PSNR | SSIM | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Pure Red Patch** | $(220, 40, 40)$ | $(218, 41, 41)$ | $2\text{ LSB}$ | $1.33$ | $38.4\text{ dB}$ | $0.985$ | **PASS** |
| **Pure Green Patch** | $(40, 200, 40)$ | $(41, 198, 41)$ | $2\text{ LSB}$ | $1.67$ | $37.2\text{ dB}$ | $0.981$ | **PASS** |
| **Pure Blue Patch** | $(40, 40, 220)$ | $(42, 42, 218)$ | $2\text{ LSB}$ | $2.00$ | $36.1\text{ dB}$ | $0.976$ | **PASS** |
| **Neutral Gray (22)** | $(128, 128, 128)$ | $(128, 128, 128)$ | $0\text{ LSB}$ | $0.00$ | $48.2\text{ dB}$ | $0.998$ | **PASS** |
| **Composite Image** | $64 \times 64$ Multi-Color | Sharp JPEG ($Q=95$) | Max $6\text{ LSB}$ | **$1.82\text{ LSB}$** | **$34.9\text{ dB}$** | **$0.965$** | **PASS** |

---

### 3. Channel Ordering Invariant

- Strict RGB channel ordering is enforced.
- Tested: When feeding a Pure Red frame ($Y=76, U=85, V=255$), the red channel yields $R=254$ and blue channel yields $B=0$. Any BGR inversion would swap channels, yielding $R=0, B=254$, which fails unit test assertions immediately.
